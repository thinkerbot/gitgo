require 'gitgo/controller'

module Gitgo
  module Controllers
    class Issue < Controller
      set :resource_name, "issue"
      set :views, "views/issue"

      get('/')       { index }
      get('/:id')    {|id| show(id) }
      get('/:id/:comment') {|id, comment| show(id, comment) }
      post('/')      { create }
      post('/:id') do |id|
        _method = request[:_method]
        case _method
        when /\Aupdate\z/i then update(id)
        when /\Adelete\z/i then destroy(id)
        else raise("unknown post method: #{_method}")
        end
      end
      put('/:id')    {|id| update(id) }
      delete('/:id') {|id| destroy(id) }
      
      INHERIT = %w{state tags}
      DEFAULT_STATES = %w{open closed}
    
      def index
        issues = repo.index("type", "issue")
      
        criteria = {}
        request.params.each_pair do |key, values|
          criteria[key] = values.kind_of?(Array) ? values : [values]
        end
      
        filters = []
        criteria.each_pair do |key, values|
          filter = values.collect do |value|
            repo.index(key, value)
          end.flatten
        
          filters << filter
        end
      
        unless filters.empty?
          issues.delete_if do |issue|
            selected = repo.tails(issue)
            filters.each do |filter|
              selected = selected & filter
            end
          
            selected.empty?
          end
        end
      
        issues.collect! {|sha| docs[sha] }
      
        erb :index, :locals => {
          :issues => issues,
          :criteria => criteria
        }
      end
    
      def create
        doc = document('type' => 'issue', 'state' => 'open')
        issue = repo.store(doc)
      
        # if specified, link the issue to a commit
        if commit = doc['at']
          repo.link(commit, issue, :ref => issue)
        end
      
        repo.commit!("added issue #{issue}") if commit?
        redirect url(issue)
      end
    
      def show(issue, comment=nil)
        unless issue_doc = docs[issue]
          raise "unknown issue: #{issue.inspect}"
        end
      
        # get children and resolve to docs
        comments = repo.comments(issue, docs)
        tails = comments.select {|doc| doc[:tail] }
        tails << issue_doc if tails.empty?
        
        merge = {:states => [], :tags => []}
        tails.each do |doc|
          merge[:states] << doc['state']
          merge[:tags].concat doc.tags
        end
        merge.each_value do |value|
          value.uniq!
        end
      
        erb :show, :locals => {
          :id => issue,
          :doc => issue_doc,
          :comments => comments,
          :tails => tails,
          :merge => merge,
          :selected => comment,
        }
      end
    
      # Update adds a comment to the specified issue.
      def update(issue)
        unless doc = docs[issue]
          raise "unknown issue: #{issue.inspect}"
        end
      
        # the comment is always in regards to the issue internally (ie re => issue)
        doc = inherit(doc, 'type' => 'update', 're' => issue)
        update = repo.store(doc)

        # link the comment to each parent and update the index
        parents = request['re'] || [issue]
        parents = [parents] unless parents.kind_of?(Array)
        parents.each {|parent| repo.link(parent, update) }
      
        # if specified, link the issue to a commit
        if commit = doc['at']
          repo.link(commit, update, :ref => issue)
        end
      
        repo.commit!("updated issue #{issue}") if commit?
        redirect url("#{issue}/#{update}")
      end
    
      #
      # helpers
      # 
    
      # Same as document, but ensures each of the INHERIT attributes is
      # inherited from doc if it is not specified in the request.
      def inherit(doc, overrides=nil)
        base = document(overrides)
        INHERIT.each {|key| base[key] ||= doc[key] }
        base
      end
      
      def refs
        grit.refs
      end
      
      def head
        @head ||= grit.head.name
      end
      
      # Returns an array of states currently in use
      def states
        (DEFAULT_STATES + repo.list("states")).uniq
      end
    
      # Returns an array of tags currently in use
      def tags
        repo.list("tags")
      end
    end
  end
end