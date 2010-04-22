require 'json'
require 'gitgo/git'
require 'gitgo/index'
require 'gitgo/repo/graph'
require 'gitgo/repo/utils'

module Gitgo
  # Repo represents the internal data store used by Gitgo. Repos consist of a
  # Git instance for storing documents in the repository, and an Index
  # instance for queries on the documents. The internal workings of Repo are a
  # bit complex; this document provides terminology and details on how
  # documents and linkages are stored.  See Index and Graph for how the stored
  # information is accessed.
  #
  # == Terminology
  #
  # Gitgo documents are hashes of attributes that can be serialized as JSON.
  # The Gitgo::Document model adds structure to these hashes and enforces data
  # validity, but insofar as Repo is concerned, a document is a serializable
  # hash. Documents are linked into a document graph -- a directed acyclic
  # graph (DAG) of document nodes that represent, for example, a chain of
  # comments making a conversation.  A given repo can be thought of as storing
  # multiple DAGs, each made up of multiple documents.
  #
  # The DAGs used by Gitgo are a little weird because they use some nodes to
  # represent revisions, and other nodes to represent the 'current' nodes in a
  # graph (this setup allows documents to be immutable, and thereby to prevent
  # merge conflicts).  
  #
  # Normally a DAG has this conceptual structure:
  #
  #   head
  #   |
  #   parent
  #   |
  #   node
  #   |
  #   child
  #   |
  #   tail
  #
  # By contrast, the DAGs used by Gitgo are structured like this:
  #
  #                           head
  #                           |
  #                           parent
  #                           |
  #   original -> previous -> node -> update -> current version
  #                           |
  #                           child
  #                           |
  #                           tail
  #
  # The extra dimension of updates may be unwound to replace all previous
  # versions of a node with the current version(s), so for example:
  #
  #               a                       a
  #               |                       |
  #               b -> b'    becomes      b'
  #               |                       |
  #               c                       c
  #
  # The full DAG is refered to as the 'convoluted graph' and the current DAG
  # is the 'deconvoluted graph'.  The logic performing the deconvolution is
  # encapsulated in Gitgo::Graph.
  #
  # Parent-child relationships are referred to as links, while previous-update
  # relationships are referred to as updates.  Links and updates are
  # collectively referred to as linkages.  The first member in a linkage
  # (parent/previous) is a source and the second (child/update) is a target.
  #
  # Deletes are supported as a special type of update where the document is
  # updated to itself; these act as a break in the DAG where all subsequent
  # links and updates are omitted.
  #             
  # == Documents and Linkages
  #
  # Documents and linkages are stored on a dedicated git branch in a way that
  # prevents merge conflicts, and allows merges to directly add nodes anywhere
  # in a document graph.  The branch may be checked out and handled like any
  # other git branch, although typically users manage the gitgo branch through
  # Gitgo itself.
  #
  # Individual documents are stored by a date/sha path like this, where sha is
  # the sha of the serialized document (ie it identifies the blob storing the
  # document):
  #
  #   path              mode    blob
  #   YYYY/MMDD/sha     100644  sha
  #
  # The path is meaningful to determine a timeline of activity without
  # examining the contents of any individual document.
  #
  # Linkages similarly incorporate document shas into their path, but split up
  # the source sha into substrings of length 2 and 38 (note that empty sha
  # refers to the sha of an empty file):
  #
  #   path              mode    blob
  #   pa/rent/child     100644  empty_sha
  #   pr/evious/update  100644  previous
  #   de/lete/delete    100644  delete
  #
  # The relationship between the source, target, and blob shas is used to
  # determine the type of linkage involved.  The logic breaks down like so:
  #
  #   source == target   blob         linkage type
  #   no                 empty_sha    link
  #   no                 source       update
  #   yes                target       delete
  #
  # Using this logic, a traveral of the linkages is enough to determine how
  # documents are related, again without loading individual documents into
  # memory.
  #
  # == Implementation Note
  #
  # Repo is organized around an env hash that represents the rack env for a
  # particular request.  Objects used by Repo are cached into env for re-use
  # across multiple requests, when possible.  The 'gitgo.*' constants are used
  # to identify cached objects.
  #
  # Repo knows how to initialize all the objects it uses.  An empty env or a
  # partially filled env may be used to initialize a Repo.
  #
  class Repo
    class << self
      
      # Initializes a new Repo to the git repository at the specified path.
      # Options are the same as for Git.init.
      def init(path, options={})
        git = Git.init(path, options)
        new(GIT => git)
      end
      
      # Sets env as the thread-specific env and returns the currently set env.
      def set_env(env)
        current = Thread.current[ENVIRONMENT]
        Thread.current[ENVIRONMENT] = env
        current
      end
      
      # Sets env for the block.
      def with_env(env)
        begin
          current = set_env(env)
          yield
        ensure
          set_env(current)
        end
      end
      
      # The thread-specific env currently in scope (see set_env).  The env
      # stores all the objects used by a Repo and typically represents the
      # rack-env for a specific server request.
      #
      # Raises an error if no env is in scope.
      def env
        Thread.current[ENVIRONMENT] or raise("no env in scope")
      end
      
      # Returns the current Repo, ie env[REPO].  Initializes and caches a new
      # Repo in env if env[REPO] is not set.
      def current
        env[REPO] ||= new(env)
      end
    end
    include Utils
    
    ENVIRONMENT  = 'gitgo.env'
    PATH         = 'gitgo.path'
    OPTIONS      = 'gitgo.options'
    GIT          = 'gitgo.git'
    INDEX        = 'gitgo.index'
    REPO         = 'gitgo.repo'
    CACHE        = 'gitgo.cache'
    
    # Matches a path -- 'ab/xyz/sha'.  After the match:
    #
    #  $1:: ab
    #  $2:: xyz
    #  $3:: sha
    #
    DOCUMENT_PATH = /^(.{2})\/(.{38})\/(.{40})$/
    
    DEFAULT_MODE  = '100644'.to_sym
    
    UPDATE_MODE   = '100640'.to_sym
    
    # The repo env, typically the same as a request env.
    attr_reader :env
    
    # Initializes a new Repo with the specified env.
    def initialize(env={})
      @env = env
    end
    
    # The gitgo head, ie the head of the branch where gitgo documents are
    # stored.
    def head
      git.head
    end
    
    # The git author, used as the default author for documents with no author.
    def author
      git.author
    end
    
    # Resolves sha (which could be a sha, a short-sha, or treeish) to a full
    # sha.  Returns nil if the sha cannot be resolved.
    def resolve(sha)
      git.resolve(sha) rescue sha
    end
    
    # Returns the path to git repository.  Path is determined from env[PATH],
    # or inferred and set in env from env[GIT].  The default path is Dir.pwd.
    def path
      env[PATH] ||= (env.has_key?(GIT) ? env[GIT].path : Dir.pwd)
    end
    
    # Returns the Git instance set in env[GIT].  If no instance is set then
    # one will be initialized using env[PATH] and env[OPTIONS].
    #
    # Note that given the chain of defaults, git will be initialized to
    # Dir.pwd if the env has no PATH or GIT set.
    def git
      env[GIT] ||= Git.init(path, env[OPTIONS] || {})
    end
    
    # Returns the Index instance set in env[INDEX].  If no instance is set then
    # one will be initialized under the git working directory, specific to the
    # git branch.  For instance:
    #
    #   .git/gitgo/refs/branch/index
    #
    def index
      env[INDEX] ||= Index.new(File.join(git.work_dir, 'refs', git.branch, 'index'))
    end
    
    # Returns or initializes a self-populating cache of attribute hashes in
    # env[CACHE]. Attribute hashes are are keyed by sha.
    def cache
      env[CACHE] ||= Hash.new {|hash, sha| hash[sha] = read(sha) }
    end
    
    # Returns the cached attrs hash for the specified sha, or nil. 
    def [](sha)
      cache[sha]
    end
    
    # Sets the cached attrs for the specified sha.
    def []=(sha, attrs)
      cache[sha] = attrs
    end
    
    def store(attrs)
      sha = git.set(:blob, JSON.generate(attrs))
      cache[sha] = attrs
      sha
    end
    
    #
    #   sh/a/empty_sha (DEFAULT_MODE, sha)
    #
    def create(sha)
      sha = store(sha) if sha.kind_of?(Hash)
      git[sha_path(sha, empty_sha)] = [DEFAULT_MODE, sha]
      sha
    end
    
    # Reads an deserializes specified hash of attrs.  If sha does not indicate
    # a blob that deserializes as JSON then read returns nil.
    def read(sha)
      begin
        JSON.parse(git.get(:blob, sha).data)
      rescue JSON::ParserError, Errno::EISDIR 
        nil
      end
    end
    
    # Creates a link file for parent and child:
    #
    #   pa/rent/child (DEFAULT_MODE, child)
    #
    def link(parent, child)
      git[sha_path(parent, child)] = [DEFAULT_MODE, child]
      index.associate(parent, child)
      self
    end
    
    # Creates an update file for old and new shas:
    #
    #   ol/d_sha/new_sha (UPDATE_MODE, new_sha)
    #
    def update(old_sha, new_sha)
      git[sha_path(old_sha, new_sha)] = [UPDATE_MODE, new_sha]
      index.associate(old_sha, new_sha)
      self
    end
    
    # Creates a delete file for the sha:
    #
    #   sh/a/sha (DEFAULT_MODE, empty_sha)
    #
    def delete(sha)
      git[sha_path(sha, sha)] = [DEFAULT_MODE, empty_sha]
      self
    end
    
    def document_sha(source, target)
      case target
      when source    then source
      when empty_sha then source
      else target
      end
    end
    
    def document_mode(source, target)
      tree = git.tree.subtree(sha_path(source))
      return nil unless tree

      mode, sha = tree[target]
      mode
    end
    
    # Returns the linkage type, given the source, target and sha.
    def document_type(source, target, mode=document_mode(source, target))
      case target
      when empty_sha then :head
      when source    then :delete
      else 
        case mode
        when DEFAULT_MODE then :link
        when UPDATE_MODE  then :update
        else :invalid
        end
      end
    end
    
    # Yield each linkage off of source to the block, with the linkage type.
    def each_document(source) # :yields: sha, type
      return self if source.nil?
      
      target_tree = git.tree.subtree(sha_path(source))
      target_tree.each_pair do |target, (mode, sha)|
        yield document_sha(source, target), document_type(source, target, mode)
      end if target_tree
      
      self
    end

    # Yields the sha of each document in the repo, in no particular order and
    # with duplicates for every link/update that has multiple parents.
    def each
      git.tree.each_pair(true) do |ab, xyz_tree|
        xyz_tree.each_pair(true) do |xyz, target_tree|
          source = "#{ab}#{xyz}"
          
          target_tree.keys.each do |target|
            doc_sha = document_sha(source, target)
            yield(doc_sha) if doc_sha
          end
        end
      end
    end
    
    # Initializes a Graph for the sha.
    def graph(sha)
      Graph.new(self, sha)
    end
    
    # Returns an array of revisions (commits) reachable from the sha.  These
    # revisions are cached into the index for quick retreival.
    def rev_list(sha)
      sha = resolve(sha)
      rev_lists = index['cache']
      
      unless rev_lists.has_key?(sha)
        rev_lists[sha] = git.rev_list(sha)
      end
      
      rev_lists[sha]
    end
    
    # Returns a list of document shas that have been added ('A') between a and
    # b. Deleted ('D') or modified ('M') documents can be specified using
    # type.
    def diff(a, b, type='A')
      if a == b || b.nil?
        return []
      end
      
      paths = a.nil? ? git.ls_tree(b) : git.diff_tree(a, b)[type]
      paths.collect! do |path|
        ab, xyz, target = path.split('/', 3)
        document_sha("#{ab}#{xyz}", target)
      end

      paths.compact!
      paths
    end
    
    # Generates a status message based on currently uncommitted changes.
    def status(&block)
      block ||= lambda {|sha| sha}
      
      lines = []
      git.status.each_pair do |path, state|
        ab, xyz, target = path.split('/', 3)
        source = "#{ab}#{xyz}"
        
        sha  = document_sha(source, target)
        type = document_type(source, target)
        
        status = case document_type(source, target)
        when :head
          create_status(sha, self[sha], &block)
        when :link
          link_status(source, target, &block)
        when :update
          update_status(source, target, &block)
        when :delete
          delete_status(sha, &block)
        else
          ['unknown', path]
        end
        
        if status
          status.unshift state_str(state)
          lines << status
        end
      end
      
      format_status(lines).join("\n")
    end
    
    # Commits any changes to git and writes the index to disk.  The commit
    # message is inferred from the status, if left unspecified.  Commit will
    # raise an error if there are no changes to commit.
    def commit(msg=status)
      sha = git.commit(msg)
      index.write(sha)
      sha
    end
    
    # Same as commit but does not check if there are changes to commit, useful
    # when you know there are changes to commit and don't want the overhead of
    # checking for changes.
    def commit!(msg=status)
      sha = git.commit!(msg)
      index.write(sha)
      sha
    end
    
    # Sets self as the current Repo for the duration of the block.
    def scope
      Repo.with_env(REPO => self) { yield }
    end
  end
end