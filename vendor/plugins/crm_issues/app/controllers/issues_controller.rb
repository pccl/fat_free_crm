class IssuesController < ApplicationController
  # Prevent error: 'A copy of ApplicationController has been removed
  # from the module tree but is still active!'
  #   http://tinyurl.com/nzu2y2
  unloadable

  before_filter :require_user
  before_filter :set_current_tab, :only => [:index]
  before_filter :get_data_for_sidebar, :only => [:index]

  # GET /issues
  # GET /issues.xml                                                        HTML
  #----------------------------------------------------------------------------
  def index
    @issues = get_issues(:page => params[:page])

    respond_to do |format|
      format.html # index.html.haml
      format.js   # index.js.rjs
      format.xml  { render :xml => @issues }
    end
  end

  # GET /issues/1
  # GET /issues/1.xml                                                      HTML
  #----------------------------------------------------------------------------
  def show
    @issue = Issue.my(@current_user).find(params[:id])
    @current_tab = :issues
    @comment = Comment.new

    respond_to do |format|
      format.html # show.html.erb
      format.js   # show.html.erb
      format.xml { render :xml => @issue }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:html, :xml)
  end

  # GET /issues/new
  # GET /issues/new.xml                                                    AJAX
  #----------------------------------------------------------------------------
  def new
    @issue    = Issue.new(:user => @current_user)
    @users    = User.except(@current_user).all
    @account  = Account.new(:user => @current_user)
    @accounts = Account.my(@current_user).all(:order => "name")

    if params[:related]
      model, id = params[:related].split("_")
      instance_variable_set("@#{model}", model.classify.constantize.my(@current_user).find(id))
    end

    respond_to do |format|
      format.js
      format.xml { render :xml => @issue }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_related_not_found(model, :js) if model
  end

  # GET /issues/1/edit                                                     AJAX
  #----------------------------------------------------------------------------
  def edit
    @issue = Issue.my(@current_user).find(params[:id])
    @users    = User.except(@current_user).all
    # FIXME!
    # The following line throws a TypeError (can't dup NilClass) error.
    # Development mode only!
    @account = @issue.account || Account.new(:user => @current_user)
    @accounts = Account.my(@current_user).all(:order => "name")
    if params[:previous] =~ /(\d+)\z/
      @previous = Issue.my(@current_user).find($1)
    end
    respond_to do |format|
      format.js
    end
  rescue ActiveRecord::RecordNotFound
    @previous ||= $1.to_i
    respond_to_not_found(:js) unless @issue
  end

  # PUT /issues/1
  # PUT /issues/1.xml                                                      AJAX
  #----------------------------------------------------------------------------
  def update
    @issue = Issue.my(@current_user).find(params[:id])
    respond_to do |format|
      if @issue.update_with_account_and_permissions(params)
        get_data_for_sidebar if called_from_index_page?
        format.js
      else
        @users = User.except(@current_user).all
        @accounts = Account.my(@current_user).all(:order => "name")
        unless params[:account][:id].blank?
          @account = Account.find(params[:account][:id])
        else
          if request.referer =~ /\/accounts\/(.+)$/
            @account = Account.find($1) # related account
          else
            @account = Account.new(:user => @current_user)
          end
        end
        format.js
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:js, :xml)
  end

  # POST /issues
  # POST /issues.xml                                                       AJAX
  #----------------------------------------------------------------------------
  def create
    @issue = Issue.new(params[:issue])

    respond_to do |format|
      if @issue.save_with_account_and_permissions(params)
        if called_from_index_page?
          @issues = get_issues
          get_data_for_sidebar
        end
        format.js
        format.xml { render :xml => @issue, :status => :created, :location => @issue }
      else
        @users = User.except(@current_user).all
        @accounts = Account.my(@current_user).all(:order => "name")
        unless params[:account][:id].blank?
          @account = Account.find(params[:account][:id])
        else
          if request.referer =~ /\/accounts\/(.+)$/
            @account = Account.find($1) # related account
          else
            @account = Account.new(:user => @current_user)
          end
        end
        format.js
        format.xml  { render :xml => @issue.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /issues/1
  # DELETE /issues/1.xml                                         HTML and AJAX
  #----------------------------------------------------------------------------
  def destroy
    @issue = Issue.my(@current_user).find(params[:id])
    @issue.destroy if @issue
    respond_to do |format|
      format.html { respond_to_destroy(:html) }
      format.js   { respond_to_destroy(:ajax) }
      format.xml  { head :ok }
    end
  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:html, :js, :xml)
  end
  
  # POST /issues/search                                                    AJAX
  #----------------------------------------------------------------------------
  def search
    @issues = get_issues(:bug_ticket => params[:bug_ticket], :query => params[:query], :page => 1)

    respond_to do |format|
      format.js   { render :action => :index }
      format.xml  { render :xml => @issues.to_xml }
    end
  end

  # POST /issues/filter                                                    AJAX
  #----------------------------------------------------------------------------
  def filter
    session[:filter_by_issue_priority] = params[:priority] if params[:priority]
    session[:filter_by_issue_status]   = params[:status] if params[:status]
    @issues = get_issues(:page => 1)
    render :action => :index
  end

  # POST /issues/resolve_bug                                               HTML
  #----------------------------------------------------------------------------
  def resolve_bug
    @issues = Issue.with_ticket(params[:bug_ticket])
    count = 0
    @issues.each do |issue|
      if issue.status == 0
        issue.update_attribute(:status, 1) 
        count += 1
        session[:bug_ticket] = nil
      end
    end
    flash[:notice] = count > 0 ?
      "#{count} issues have been upgraded to status 'Bug resolved'" :
      "No unresolved issues could be found with that bug ticket"

    redirect_to :action => :index
  end

  private

  def get_issues(options = { :page => nil, :query => nil, :bug_ticket => nil })
    self.current_page = options[:page]           if options[:page]
    self.current_query = options[:query]         if options[:query]
    self.bug_ticket = options[:bug_ticket]       if options[:bug_ticket]

    records = {
      :user => @current_user
    }
    pages = {
      :page => current_page,
      :per_page => @current_user.pref[:accounts_per_page]  # TODO: create a :issues_per_page preference
    }

    full_query = Issue.my(records)
    full_query = full_query.search(current_query)        unless current_query.blank?
    full_query = full_query.with_ticket(bug_ticket)      unless bug_ticket.blank?

    if session[:filter_by_issue_status]
      self.statuses = session[:filter_by_issue_status].split(",")
      full_query = full_query.only_statuses(statuses)
    end

    if session[:filter_by_issue_priority]
      self.priorities = session[:filter_by_issue_priority].split(",")
      full_query = full_query.only_priorities(priorities)
    end

    full_query.paginate(pages)
  end

  def respond_to_destroy(method)
    if method == :ajax
      if called_from_index_page?
        get_data_for_sidebar
        @issues = get_issues
        if @issues.blank?
          @issues = get_issues(:page => current_page - 1) if current_page > 1
          render :action => :index and return
        end
      else # called from related asset.
        self.current_page = 1
      end
      # At this point, render destroy.js.rjs
    else
      self.current_page = 1
      flash[:notice] = "#{@issue.name} has been deleted."
      redirect_to(issues_path)
    end
  end

  def get_data_for_sidebar
    @issue_priority_total = { :all => Issue.my(@current_user).count }
    # TODO - store/fetch priorities from Settings
    ["low", "minor", "major", "critical"].each do |p|
      @issue_priority_total[p] = Issue.my(@current_user).with_priority(p).count
    end

    @issue_status_total = { }
    Issue.allowed_statuses.each do |pair|
      name, index = pair
      @issue_status_total[index] = Issue.my(@current_user).with_status(index).count
    end
  end

  def statuses=(statuses)
    @statuses = session[:statuses] = statuses
  end

  def statuses
    @statuses = params[:statuses] || session[:statuses] || ""
  end

  def priorities=(priorities)
    @priorities = session[:priorities] = priorities
  end

  def priorities
    @priorities = params[:priorities] || session[:priorities] || ""
  end

  def bug_ticket=(bug_ticket)
    @bug_ticket = session[:bug_ticket] = bug_ticket
  end

  def bug_ticket
    @bug_ticket = params[:bug_ticket] || session[:bug_ticket] || ""
  end

end
