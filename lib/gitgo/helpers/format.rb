require 'rack/utils'
require 'redcloth'

module Gitgo
  module Helpers
    class Format
      include Rack::Utils
      
      attr_reader :controller
      
      def initialize(controller)
        @controller = controller
      end
      
      def url(*paths)
        controller.url(paths)
      end
      
      #
      # general formatters
      #
      
      def text(str)
        str = escape_html(str)
        str.gsub!(/[A-Fa-f\d]{40}/) {|sha| sha_a(sha) }
        str
      end
      
      def sha(sha)
        escape_html(sha)
      end
      
      def textile(str)
        ::RedCloth.new(str).to_html
      end
      
      #
      # links
      #
      
      def sha_a(sha)
        "<a class=\"sha\" href=\"#{url('obj', sha)}\" title=\"#{sha}\">#{sha}</a>"
      end
      
      def path_a(type, treeish, path)
        "<a class=\"#{type}\" href=\"#{url(type, treeish, *path)}\">#{escape_html(path.pop || treeish)}</a>"
      end
      
      def full_path_a(type, treeish, path)
        "<a class=\"#{type}\" href=\"#{url(type, treeish, *path)}\">#{escape_html File.join(path)}</a>"
      end
      
      def commit_a(treeish)
        "<a class=\"commit\" href=\"#{url('commit', treeish)}\">#{escape_html treeish}</a>"
      end
      
      def tree_a(treeish, *path)
        path_a('tree', treeish, path)
      end
      
      def blob_a(treeish, *path)
        path_a('blob', treeish, path)
      end
      
      def history_a(treeish)
        "<a class=\"history\" href=\"#{url('commits', treeish)}\" title=\"#{escape_html treeish}\">history</a>"
      end
      
      def issue_a(doc)
        title = doc.title
        title = "(nameless issue)" if title.to_s.empty?
        state = doc.state
        
        "<a class=\"#{escape_html state}\" id=\"#{doc.sha}\" active=\"#{doc.active?}\" href=\"#{url('issue', doc.sha)}\">#{escape_html title}</a>"
      end
      
      def index_key_a(key)
        "<a href=\"#{url('repo', 'idx', key)}\">#{escape_html key}</a>"
      end
      
      def index_value_a(key, value)
        "<a href=\"#{url('repo', 'idx', key, value)}\">#{escape_html value}</a>"
      end
      
      def each_path(treeish, path)
        paths = path.split("/")
        base = paths.pop
        paths.unshift(treeish)

        object_path = ['tree']
        paths.collect! do |path| 
          object_path << path
          yield "<a href=\"#{url(*object_path)}\">#{escape_html path}</a>"
        end

        yield(base) if base
        paths
      end
      
      def each_activity(timeline)
        timeline.reverse_each do |doc|
          type_a = case doc.type
          when 'comment'
            sha_a doc.re
          when 'issue'
            issue_a doc
          when 'update'   
            issue_doc = Document[doc.re]
            issue_a issue_doc
          else 
            sha_a doc.sha
          end
          
          type = (doc.type || 'unknown').capitalize
          yield(escape_html(type), type_a, author(doc.author), date(doc.date))
        end
      end
      
      #
      # documents
      #
      
      # a document title
      def title(title)
        escape_html(title)
      end
      
      def content(str)
        textile text(str)
      end
      
      def author(author)
        "#{escape_html(author.name)} (<a href=\"#{url('timeline')}?#{build_query(:author => author.email)}\">#{escape_html author.email}</a>)"
      end
      
      def date(date)
        "<abbr title=\"#{date.iso8601}\">#{date.strftime('%Y/%m/%d %H:%M %p')}</abbr>"
      end
      
      def at(at)
        sha(at)
      end
      
      def re(re)
        sha(re)
      end
      
      def tags(tags)
        # add links/clouds
        escape_html tags.join(', ')
      end
      
      def state(state)
        escape_html state
      end
      
      def states(states)
        escape_html states.join(', ')
      end
      
      #
      # repo
      #
      
      def path(path)
        escape_html(path)
      end
      
      def branch(branch)
        escape_html(branch)
      end
      
      def each_diff_a(status)
        status.keys.sort.each do |path|
          change, a, b = status[path]
          a_mode, a_sha = a
          b_mode, b_sha = b
          
          yield "<a class=\"#{change}\" href=\"#{url('obj', b_sha.to_s)}\" title=\"#{a_sha || '-'} to #{b_sha || '-'}\">#{path}</a>"
        end
      end
    end
  end
end
