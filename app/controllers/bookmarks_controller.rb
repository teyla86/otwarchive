class BookmarksController < ApplicationController 
  before_filter :load_bookmarkable, :only => [ :index, :new, :create, :fetch_recent ]
  before_filter :check_user_status, :only => [:new, :create, :edit, :update]
  before_filter :load_bookmark, :only => [ :show, :edit, :update, :destroy, :fetch_recent ] 
  before_filter :check_visibility, :only => [ :show ]
  before_filter :check_ownership, :only => [ :edit, :update, :destroy ]
  
  # get the parent
  def load_bookmarkable
    if params[:work_id]
      @bookmarkable = Work.find(params[:work_id])
    elsif params[:external_work_id]
      @bookmarkable = ExternalWork.find(params[:external_work_id])
    elsif params[:series_id]
      @bookmarkable = Series.find(params[:series_id])
    end
  end  

  def load_bookmark
    @bookmark = Bookmark.find(params[:id])
    @check_ownership_of = @bookmark
    @check_visibility_of = @bookmark
  end

  
  # GET    /:locale/bookmarks
  # GET    /:locale/users/:user_id/bookmarks
  # GET    /:locale/works/:work_id/bookmarks
  # GET    /:locale/external_works/:external_work_id/bookmarks
  def index
    if params[:user_id]
      @user = User.find_by_login(params[:user_id])
      owner = @user
    end
    if params[:pseud_id] && @user
      @author = @pseud = @user.pseuds.find_by_name(params[:pseud_id])
      # @author is needed in the sidebar and I'm too lazy to redo the whole thing
      owner = @pseud
    elsif params[:tag_id]
      owner ||= Tag.find_by_name(params[:tag_id])
    else
      owner ||= @bookmarkable
    end
    # Do not want to aggregate bookmarks on these pages
    if params[:pseud_id] || params[:user_id] || params[:work_id] || params[:external_work_id] || params[:series_id]
      if params[:existing] && params[:recs_only]
        search_by = "owner.bookmarks.find(:all, :conditions => ['rec = (?) AND pseud_id IN (?)', true, current_user.pseuds.collect(&:id)])"
      elsif params[:existing]
        search_by = "owner.bookmarks.find(:all, :conditions => ['pseud_id IN (?)', current_user.pseuds.collect(&:id)])"
      elsif params[:recs_only]
        search_by = "owner.bookmarks.recs.visible"
      else
        search_by = "owner.bookmarks.visible"
      end
      @bookmarks = eval(search_by).sort_by(&:created_at).reverse.paginate(:page => params[:page])
    else # Aggregate on main bookmarks page, tag page
      if params[:tag_id]
        @most_recent_bookmarks = false
        # Want to get not only bookmarks with tag, but also bookmarks on works with tag
        @works_with_tag = owner.works.visible.collect{|w| ["Work", w.id]}
        @external_works_with_tag = owner.external_works.visible.collect{|ew| ["ExternalWork", ew.id]}
        @bookmarks_with_tag = owner.bookmarks.visible.collect{|b| [b.bookmarkable_type, b.bookmarkable_id]}.uniq
        @bookmarkables = @bookmarks_with_tag | @works_with_tag | @external_works_with_tag
      else # Show only bookmarks from past month on main page
        @most_recent_bookmarks = true
        @bookmarkables = Bookmark.recent.visible.collect{|b| [b.bookmarkable_type, b.bookmarkable_id]}.uniq
      end
      @bookmarks = []
      search_by = params[:recs_only] ? "eval(b[0]).find(b[1]).bookmarks.recs.visible" : "eval(b[0]).find(b[1]).bookmarks.visible"
      @bookmarkables.each do |b|
        if eval(b[0]).exists?(b[1])
          @bookmarks << eval(search_by).last unless eval(search_by).blank?
        end
      end
      @bookmarks = @bookmarks.sort_by(&:created_at).reverse.paginate(:page => params[:page])
    end
    if @bookmarkable
      access_denied unless is_admin? || @bookmarkable.visible
    end
  end
  
  # GET    /:locale/bookmark/:id
  # GET    /:locale/users/:user_id/bookmarks/:id
  # GET    /:locale/works/:work_id/bookmark/:id
  # GET    /:locale/external_works/:external_work_id/bookmark/:id
  def show
  end

  # GET /bookmarks/new
  # GET /bookmarks/new.xml
  def new
    @bookmark = Bookmark.new
    respond_to do |format|
      format.html
      format.js
    end
  end

  # GET /bookmarks/1/edit
  def edit
    @bookmarkable = @bookmark.bookmarkable
    @tag_string = @bookmark.tag_string
  end

  # POST /bookmarks
  # POST /bookmarks.xml
  def create
    @bookmark = Bookmark.new(params[:bookmark])
    unless params[:fetched].blank? || params[:fetched][:value].blank?
      fandom_string = params[:bookmark][:external][:fandom_string].to_s
      rating_string = params[:bookmark][:external][:rating_string].to_s
      category_string = params[:bookmark][:external][:category_string].to_s
      pairing_string = params[:bookmark][:external][:pairing_string].to_s
      character_string = params[:bookmark][:external][:character_string].to_s
    @bookmark.set_external(params[:fetched][:value].to_i, fandom_string, rating_string, category_string, pairing_string, character_string)
    end
    begin
      if @bookmark.save && @bookmark.tag_string=params[:tag_string]
        flash[:notice] = t('successfully_created', :default => 'Bookmark was successfully created.')
       redirect_to(@bookmark) 
      else
        raise
      end
    rescue
      @bookmarkable = @bookmark.bookmarkable || ExternalWork.new
      render :action => "new" 
    end 
  end

  # PUT /bookmarks/1
  # PUT /bookmarks/1.xml
  def update
    begin
      if @bookmark.update_attributes(params[:bookmark]) && @bookmark.tag_string=params[:tag_string]
        flash[:notice] = t('successfully_updated', :default => 'Bookmark was successfully updated.')
       redirect_to(@bookmark) 
      else
        raise
      end
    rescue
      @bookmarkable = @bookmark.bookmarkable || ExternalWork.new
      render :action => :edit
    end
  end

  # DELETE /bookmarks/1
  # DELETE /bookmarks/1.xml
  def destroy
    @bookmark.destroy
    flash[:notice] = t('successfully_deleted', :default => 'Bookmark was successfully deleted.')
   redirect_to user_bookmarks_path(current_user)
  end

  # Used on index page to show 4 most recent bookmarks (after bookmark being currently viewed) via RJS
  # Only main bookmarks page or tag bookmarks page
  # No direct non-JS fallback, as we have the 'view all bookmarks' link which serves the same function
  def fetch_recent
    if request.xml_http_request?
      @bookmarkable = @bookmark.bookmarkable
      @recent_bookmarks = @bookmarkable.bookmarks.visible(:order => "created_at DESC", :limit => 4, :offset => 1)
        respond_to do |format|
        format.js
      end
    else # redirect if not AJAX, e.g. if redirected from login form
      if params[:tag_id]
        redirect_to :action => 'index', :tag_id => params[:tag_id]
      else
        redirect_to bookmarks_path
      end
    end
  end

end
