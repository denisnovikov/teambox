class UploadsController < ApplicationController
  before_filter :find_upload, :only => [:destroy, :update, :thumbnail, :show, :edit, :rename]
  skip_before_filter :load_project, :only => [:download]
  before_filter :set_page_title
  before_filter :load_folder, :only => :index
  before_filter :check_private_download_access, :only => :download
  before_filter :check_public_download_access, :only => :tokenized_download
  
  rescue_from CanCan::AccessDenied do |exception|
    respond_to do |f|
      error_message = "You are not allowed to do that!"
      f.js             { render :text => "alert('#{error_message}')" }
      f.any(:html, :m) { render :text => "alert('#{error_message}')" }
    end
  end

  def tokenized_download
    @extra_sendfile_options = {:disposition => 'inline'}
    download
  end

  def download
    
    if !!Teambox.config.amazon_s3
      unless @upload.asset.exists?(params[:style])
        head(:bad_request)
        raise "Unable to download file"
      end
      redirect_to @upload.s3_url(params[:style])
    else
      path = @upload.asset.path(params[:style])
      unless File.exist?(path)
        head(:bad_request)
        raise "Unable to download file"
      end  

      mime_type = File.mime_type?(@upload.asset_file_name)

      mime_type = 'application/octet-stream' if mime_type == 'unknown/unknown'

      send_file_options = {:type => mime_type}.merge(@extra_sendfile_options || {})

      response.headers['Cache-Control'] = 'private, max-age=31557600'

      path = Pathname.new(path)
      send_file(path.realpath, send_file_options)
    end
  end

  def public_download
    @upload = @current_project.uploads.find(params[:id])
    render :public_download, :layout => false
  end

  def email_public
    @upload = @current_project.uploads.find(params[:id])
    @upload.invited_user_email = params[:upload][:invited_user_email]

    if @upload.valid?
      @upload.send_public_download_email
      flash[:notice] = t('uploads.public_download.email.sent', :email => @upload.invited_user_email)
    else
      flash[:error] = t('uploads.public_download.email.not_sent', :error => @upload.errors.full_messages.to_sentence)
    end

    redirect_to @upload.parent_folder ? project_folder_path(@current_project, @upload.parent_folder) : project_uploads_path(@current_project)
  end

  def index

    # TODO: Ensure you are able to view this folder
    @uploads = @current_project.uploads.
                       where(['uploads.is_private = ? OR (uploads.is_private = ? AND watchers.user_id = ?)', false, true, current_user.id]).
                       where(:parent_folder_id => @current_folder).
                       joins("LEFT JOIN comments ON comments.id = uploads.comment_id").
                       joins("LEFT JOIN watchers ON (comments.target_id = watchers.watchable_id AND watchers.watchable_type = comments.target_type) AND watchers.user_id = #{current_user.id}").
                       includes(:user).
                       order('updated_at DESC')
    @folders = @current_project.folders.
                       where(:parent_folder_id => @current_folder, :deleted => false).
                       order('name DESC')
    @upload ||= @current_project.uploads.new

    unless params[:extractparts]
      respond_to do |format|
        format.js   { render "browsing", :layout => false }
        format.any(:html, :m) {}
      end
    end

  end

  def show
    authorize! :show, @upload
    redirect_to @upload.url
  end

  def create
    authorize! :upload_files, @current_project
    authorize! :update, @page if @page
    @upload = @current_project.uploads.new params[:upload]
    @upload.user = current_user
    @page = @upload.page
    calculate_position(@upload) if @page
    
    @upload.save!

    respond_to do |wants|
      wants.any(:html, :m) {
        if @upload.new_record?
          flash.now[:error] = "There was an error uploading the file"
          render :new
        elsif @upload.page
          if iframe?
            code = render_to_string 'create.js.rjs', :layout => false
            render :template => 'shared/iframe_rjs', :layout => false, :locals => { :code => code }
          else
            redirect_to [@current_project, @upload.page]
          end
        else
          redirect_to(@upload.parent_folder_id ? project_folder_path(@current_project, @upload.parent_folder_id) : [@current_project, :uploads])
        end
      }
    end
  end

  def update
    authorize! :update, @upload
    @upload.update_attributes(params[:upload])

    respond_to do |format|
      format.js   { render :layout => false }
      format.any(:html, :m)  { redirect_to project_uploads_path(@current_project) }
    end
  end

  def destroy
    authorize! :destroy, @upload
    @slot_id = @upload.page_slot.try(:id)
    @upload.try(:destroy)

    respond_to do |f|
      f.js   { render :layout => false }
      f.any(:html, :m) do
        flash[:success] = t('deleted.upload', :name => @upload.to_s)
        redirect_to project_uploads_path(@current_project)
      end
    end
  end
  
  def edit
    authorize! :update, @upload

    respond_to do |f|
      f.js { render :layout => false }
      #f.any(:html, :m)
    end
  end

  def rename
    authorize! :update, @upload
    @rename_successful = @upload.rename_asset((params[:upload] || {})[:asset_file_name])
    
    respond_to do |f|
      f.js { render :layout => false }
      f.any(:html, :m) do
        if @rename_successful
          flash[:notice] = t('uploads.rename.success')
        else
          flash[:error] =  [t('uploads.rename.error'), @upload.errors.full_messages.to_sentence].join('. ')
        end
        redirect_to @upload.parent_folder ? 
          project_folder_path(@current_project, @upload.parent_folder) : 
          project_uploads_path(@current_project)
      end
    end
  end
    
  private

    def check_private_download_access
      head(:not_found) and return if (@upload = Upload.find_by_id(params[:id])).nil?
      head(:forbidden) and return unless @upload.downloadable?(current_user)
    end

    def check_public_download_access
      head(:not_found) and return if (@upload = Upload.find_by_token(params[:token])).nil?
      head(:forbidden) and return unless @upload.public_downloadable?
    end

    def find_upload
      if params[:id].to_s.match /^\d+$/
        @upload = @current_project.uploads.find(params[:id])
      else
        @upload = @current_project.uploads.find_by_asset_file_name(params[:id])
      end
    end

    def load_folder
      if folder_id = params[:folder_id] || params[:id]
        unless @current_folder = Folder.find_by_id(folder_id)
          flash[:error] = t('not_found.folder', :id => folder_id)
          redirect_to project_uploads_path(@current_project) and return
        end
        @parent_folder = @current_folder.parent_folder
      end
    end

end
