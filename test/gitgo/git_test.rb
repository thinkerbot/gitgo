require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/git'

class GitTest < Test::Unit::TestCase
  include RepoTestHelper
  Git = Gitgo::Git
  
  attr_writer :git
  
  def setup
    super
    @git = nil
  end
  
  def git
    @git ||= Git.init(method_root.path)
  end
  
  def setup_repo(repo)
    @git = Git.new(super(repo), :branch => "master")
  end
  
  #
  # documentation test
  #
  
  def test_git_documentation
    git = Git.init(method_root.path("example"), :author => "John Doe <jdoe@example.com>")
    git.add(
      "README" => "New Project",
      "lib/project.rb" => "module Project\nend"
    ).commit("added files")
  
    expected = {
      "README" => [:"100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
      "lib"    => {
        "project.rb" => [:"100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"]
      }
    }
    assert_equal expected, git.tree
  
    git.reset
    expected = {
      "README" => [:"100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
      :lib     => [:"040000", "cad0dc0df65848aa8f3fee72ce047142ec707320"]
    }
    assert_equal expected, git.tree
  
    git.add("lib/project/utils.rb" => "module Project\n  module Utils\n  end\nend")
    expected = {
      "README" => [:"100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
      "lib"    => {
        "project.rb" => [:"100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"],
        "project" => {
          "utils.rb" => [:"100644", "c4f9aa58d6d5a2ebdd51f2f628b245f9454ff1a4"]
        }
      }
    }
    assert_equal expected, git.tree
  
    git.rm("README")
    expected = {
      "lib"    => {
        "project.rb" => [:"100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"],
        "project" => {
          "utils.rb" => [:"100644", "c4f9aa58d6d5a2ebdd51f2f628b245f9454ff1a4"]
        }
      }
    }
    assert_equal expected, git.tree
  
    expected = {
      "README" => :rm,
      "lib/project/utils.rb" => :add
    }
    assert_equal expected, git.status
  end
  
  #
  # version test
  #
  
  def version_ok?(required, actual)
    (required <=> actual) <= 0
  end
  
  def test_version_ok
    # equal
    assert_equal true, version_ok?([1,6,4,2], [1,6,4,2])
    
    # last slot
    assert_equal true, version_ok?([1,6,4,2], [1,6,4,3])
    assert_equal false, version_ok?([1,6,4,2], [1,6,4,1])
    
    # middle slot
    assert_equal true, version_ok?([1,6,4,2], [1,7,4,2])
    assert_equal false, version_ok?([1,6,4,2], [1,5,4,2])
    
    # unequal slots
    assert_equal true, version_ok?([1,6,4,2], [1,6,4,2,1])
    assert_equal false, version_ok?([1,6,4,2], [1,6])
    assert_equal true, version_ok?([1,6,4,2], [1,7])
  end
  
  def test_version_returns_an_array_of_integers
    version = Git.version
    assert_equal Array, version.class
    assert_equal true, version.all? {|item| item.kind_of?(Integer) }
  end
  
  #
  # init test
  #
  
  def test_init_initializes_non_existant_repos
    path = method_root.path
    assert !File.exists?(path)
    
    git = Git.init(path)
    
    git_path = method_root.path(".git")
    assert File.exists?(git_path)
    assert_equal git_path, git.grit.path
    assert_equal false, git.grit.bare
    
    git.add("path" => "content").commit("initial commit")
    assert_equal "content", git["path"]
  end
  
  def test_init_initializes_bare_repo_if_specified
    path = method_root.path
    assert !File.exists?(path)
    
    git = Git.init(path, :is_bare => true)
    
    assert !File.exists?(method_root.path(".git"))
    assert File.exists?(path)
    assert_equal path, git.grit.path
    assert_equal true, git.grit.bare
    
    git.add("path" => "content").commit("initial commit")
    assert_equal "content", git["path"]
  end
  
  def test_init_allows_specification_of_alternative_default_modes
    git = Git.init(method_root.path,
      :default_blob_mode => '100600',
      :default_tree_mode => '040777'
    )
    
    assert_equal '100600'.to_sym, git.default_blob_mode
    assert_equal '040777'.to_sym, git.default_tree_mode
  end
  
  #
  # author test
  #
  
  def test_author_determines_a_default_author_from_the_git_config
    setup_repo("simple.git")
    
    author = git.author
    assert_equal "John Doe", author.name
    assert_equal "john.doe@email.com", author.email
  end
  
  #
  # track test
  #
  
  def test_track_sets_the_upstream_branch
    setup_repo('simple.git')
    clone = git.clone(method_root.path('clone'))
    
    assert_equal 'master', clone.branch
    assert_equal 'origin', clone.grit.config['branch.master.remote']
    assert_equal 'refs/heads/master', clone.grit.config['branch.master.merge']
    assert_equal 'origin/master', clone.upstream_branch
    
    clone.track 'origin/xyz'
    
    assert_equal 'origin', clone.grit.config['branch.master.remote']
    assert_equal 'refs/heads/xyz', clone.grit.config['branch.master.merge']
    assert_equal 'origin/xyz', clone.upstream_branch
  end
  
  def test_track_with_nil_upstream_branch_removes_tracking_configs
    setup_repo('simple.git')
    
    git.grit.config['branch.master.remote'] = 'origin'
    git.grit.config['branch.master.merge'] = 'refs/heads/xyz'
    
    git.track nil
    
    assert_equal nil, git.grit.config['branch.master.remote']
    assert_equal nil, git.grit.config['branch.master.merge']
  end
  
  #
  # upstream_branch test
  #
  
  def test_upstream_branch_returns_the_upstream_branch_as_specified_by_tracking_configs
    setup_repo('simple.git')
    
    assert_equal nil, git.upstream_branch
    
    git.grit.config['branch.master.remote'] = 'origin'
    git.grit.config['branch.master.merge'] = 'refs/heads/abc'
    
    assert_equal "origin/abc", git.upstream_branch
  end
  
  #
  # remote test
  #
  
  def test_remote_returns_origin_or_configured_remote
    setup_repo('simple.git')
    assert_equal 'origin', git.remote
    
    git.grit.config['branch.master.remote'] = 'alt'
    assert_equal 'alt', git.remote
  end
  
  #
  # get test
  #
  
  def test_get_returns_the_specified_object
    setup_repo("simple.git")
    
    blob = git.get(:blob, "32f1859c0aaf1394789093c952f2b03ab04a1aad")
    assert_equal Grit::Blob, blob.class
    assert_equal "Contents of file ONE.", blob.data
    
    tree = git.get(:tree, "09aa1d0c0d69df84464b72623628acf5c63c79f0")
    assert_equal Grit::Tree, tree.class
    assert_equal ["two", "two.txt"], tree.contents.collect {|obj| obj.name }.sort
    
    commit = git.get(:commit, "ee9a1ca4441ab2bf937808b26eab784f3d041643")
    assert_equal Grit::Commit, commit.class
    assert_equal "added files x, y, and z", commit.message
    
    tag = git.get(:tag, "d0ad2534e98f0a2b9573af0355d7371468eb77f1")
    assert_equal Grit::Tag, tag.class
    assert_equal "only-123", tag.name
    assert_equal "449b5502e8dc49264d862b4fc0c01ba115fc9f82", tag.commit.id
  end
  
  #
  # set test
  #
  
  def test_set_writes_an_object_of_the_specified_type_to_repo
    id = git.set(:blob, "new content")
    assert_equal "new content", git.get(:blob, id).data
  end
  
  #
  # AGET test
  #

  def test_AGET_returns_the_contents_of_the_object_at_path
    setup_repo("simple.git")
    
    assert_equal ["one", "one.txt", "x", "x.txt"], git[""].sort
    assert_equal ["one", "one.txt", "x", "x.txt"], git["/"].sort
    assert_equal ["two", "two.txt"], git["one"].sort
    assert_equal ["two", "two.txt"], git["/one"].sort
    assert_equal ["two", "two.txt"], git["/one/"].sort
    
    assert_equal "Contents of file ONE.", git["one.txt"]
    assert_equal "Contents of file ONE.", git["/one.txt"]
    assert_equal "Contents of file TWO.", git["/one/two.txt"]
  
    assert_equal nil, git["/non_existant"]
    assert_equal nil, git["/one/non_existant.txt"]
    assert_equal nil, git["/one/two.txt/path_under_a_blob"]
  end
  
  def test_AGET_accepts_array_paths
    setup_repo("simple.git")
  
    assert_equal ["one", "one.txt", "x", "x.txt"], git[[]].sort
    assert_equal ["one", "one.txt", "x", "x.txt"], git[[""]].sort
    assert_equal ["two", "two.txt"], git[["one"]].sort
    assert_equal ["two", "two.txt"], git[["", "one", ""]].sort
    assert_equal "Contents of file ONE.", git[["", "one.txt"]]
    assert_equal "Contents of file TWO.", git[["one", "two.txt"]]
  
    assert_equal nil, git[["non_existant"]]
    assert_equal nil, git[["one", "non_existant.txt"]]
    assert_equal nil, git[["one", "two.txt", "path_under_a_blob"]]
  end
  
  def test_AGET_is_not_destructive_to_array_paths
    setup_repo("simple.git")
  
    array = ["", "one", ""]
    assert_equal ["two", "two.txt"], git[array].sort
    assert_equal ["", "one", ""], array
  end
  
  def test_AGET_returns_full_entry_if_specified
    setup_repo("simple.git")
    
    assert_equal ["one", "one.txt", "x", "x.txt"], git['', true].keys.sort
    assert_equal ["two", "two.txt"], git["/one", true].keys.sort
    assert_equal [Git::DEFAULT_BLOB_MODE, "32f1859c0aaf1394789093c952f2b03ab04a1aad"], git["one.txt", true]
  end
  
  def test_AGET_returns_committed_content_if_specified
    setup_repo("simple.git")
  
    assert_equal "Contents of file ONE.", git["one.txt"]
    git.tree["one.txt"] = [Git::DEFAULT_BLOB_MODE, git.set(:blob, "new content")]
    
    assert_equal "new content", git["one.txt"]
    assert_equal "Contents of file ONE.", git["one.txt", false, true]
  end
  
  #
  # ASET test
  #

  def test_ASET_adds_string_content_as_a_blob
    assert_equal nil, git["/a/b.txt"]
    git["/a/b.txt"] = "content"
    assert_equal "content", git["/a/b.txt"]
  end
  
  def test_ASET_adds_array_content
    sha = git.set(:blob, 'content')
    
    git["/a/b.txt"] = [Git::DEFAULT_BLOB_MODE, sha]
    assert_equal "content", git["/a/b.txt"]
  end
  
  def test_ASET_adds_symbol_content_as_a_sha
    sha = git.set(:blob, 'content')
    
    git["/a/b.txt"] = sha.to_sym
    assert_equal "content", git["/a/b.txt"]
  end
  
  def test_new_blob_content_is_not_committed_automatically
    git["/a/b.txt"] = "content"
    assert_equal nil, git["/a/b.txt", false, true]
  end

  def test_ASET_sets_content_using_default_blob_mode
    git.default_blob_mode = '100640'
    git["/a.txt"] = "content"
    assert_equal '100640'.to_sym, git["/a.txt", true][0]
  end
  
  #
  # commit test
  #
  
  def test_commit_raises_error_if_there_are_no_staged_changes
    err = assert_raises(RuntimeError) { git.commit("no changes!") }
    assert_equal "no changes to commit", err.message
  end
  
  #
  # status test
  #
  
  def test_status_returns_hash_of_staged_changes
    setup_repo("simple.git")
    
    assert_equal({}, git.status)
    
    git.add(
      "a.txt" => "file a content",
      "a/b.txt" => "file b content",
      "a/c.txt" => "file c content"
    )
    
    assert_equal({
      "a.txt" => :add,
      "a/b.txt" => :add,
      "a/c.txt" => :add
    }, git.status)
    
    git.rm("one", "one.txt", "a/c.txt")
    
    assert_equal({
      "a.txt" => :add,
      "a/b.txt" => :add,
      "one.txt" => :rm,
      "one/two.txt" => :rm,
      "one/two/three.txt"=>:rm
    }, git.status)
  end
  
  #
  # checkout test
  #
  
  def test_checkout_resets_branch_if_specified
    setup_repo("simple.git")
    
    assert_equal "master", git.branch
    assert_equal ["one", "one.txt", "x", "x.txt"], git["/"].sort
    
    assert_equal git, git.checkout("diff")
    
    assert_equal "diff", git.branch
    assert_equal ["alpha.txt", "one", "x", "x.txt"], git["/"].sort
  end
  
  def test_checkout_checks_the_repo_out_into_work_tree_in_the_block
    setup_repo("simple.git")
    
    result = git.checkout do |work_tree|
      assert File.directory?(work_tree)
      assert_equal "Contents of file TWO.", File.read(File.join(work_tree, "/one/two.txt"))
    end
    assert_equal git, result
  end
  
  def paths_in(dir)
    Dir.glob("#{dir}/*").collect {|path| File.basename(path) }.sort
  end
  
  def test_checkout_does_not_mess_with_current_index_and_work_tree
    simple = File.expand_path('simple.git', FIXTURE_DIR)
    a = method_root.path('a')
    
    `git clone '#{simple}' '#{a}'`
    
    original_index = File.read("#{a}/.git/index")
    assert_equal ["one", "one.txt", "x", "x.txt"], paths_in(a)
    
    git = Git.new(a, :branch => 'c6746dd1882d772e540342f8e180d3125a9364ad')
    git.checkout do |work_tree|
      assert_equal ["one", "one.txt"], paths_in(work_tree)
      assert_equal ["one", "one.txt", "x", "x.txt"], paths_in(a)
      assert_equal original_index, File.read("#{a}/.git/index")
    end
    
    assert_equal ["one", "one.txt", "x", "x.txt"], paths_in(a)
    assert_equal original_index, File.read("#{a}/.git/index")
  end
  
  #
  # fetch test
  #
  
  def test_fetch_fetches_updates_from_remote
    simple = File.expand_path('simple.git', FIXTURE_DIR)
    a = Git.init method_root.path('a')
    
    assert_equal [], a.grit.remotes
    
    a.sandbox do |git, work_tree, index_file|
      git.remote({}, 'add', 'simple', simple)
    end
    
    a.fetch('simple')
    assert_equal true, File.exists?(a.path("FETCH_HEAD"))
    
    remotes = a.grit.remotes.collect {|remote| remote.name }
    assert_equal ['simple/caps', 'simple/diff', 'simple/master', 'simple/xyz'].sort, remotes.sort
  end
  
  #
  # merge? test
  #
  
  def test_merge_returns_true_if_there_is_an_update_available_for_branch
    a = Git.init(method_root.path("a"))
    a.add("one" => "a one").commit("added a file")
    b = a.clone(method_root.path("b"))
    
    assert_equal false, b.merge?
    b.fetch
    assert_equal false, b.merge?

    a.add("two" => "a two").commit("added a file")
    
    assert_equal false, b.merge?
    b.fetch
    assert_equal true, b.merge?
    
    #
    c = a.clone(method_root.path("c"))
    
    assert_equal false, c.merge?
    c.fetch
    assert_equal false, c.merge?

    a.add("three" => "a three").commit("added a file")
    c.add("four"  => "b four").commit("added a file")
    
    assert_equal false, c.merge?
    c.fetch
    assert_equal true, c.merge?
  end
  
  #
  # clone test
  #
  
  def test_clone_clones_a_repository
    a = Git.init(method_root.path("a"))
    a.add("a" => "a content").commit("added a file")
    
    b = a.clone(method_root.path("b"))
    b.add("b" => "b content").commit("added a file")
    
    assert_equal a.branch, b.branch
    assert_equal method_root.path("a/.git"), a.path
    assert_equal method_root.path("b/.git"), b.path
    assert_equal false, a.grit.bare
    assert_equal false, b.grit.bare
    
    assert_equal "a content", a["a"]
    assert_equal nil, a["b"]
    assert_equal "a content", b["a"]
    assert_equal "b content", b["b"]
  end
  
  def test_clone_clones_a_bare_repository
    a = Git.init(method_root.path("a.git"))
    a.add("a" => "a content").commit("added a file")
    
    b = a.clone(method_root.path("b.git"), :bare => true)
    b.add("b" => "b content").commit("added a file")
  
    assert_equal a.branch, b.branch
    assert_equal method_root.path("a.git"), a.path
    assert_equal method_root.path("b.git"), b.path
    assert_equal true, a.grit.bare
    assert_equal true, b.grit.bare
    
    assert_equal "a content", a["a"]
    assert_equal nil, a["b"]
    assert_equal "a content", b["a"]
    assert_equal "b content", b["b"]
  end
  
  def test_clone_pulls_from_origin
    a = Git.init(method_root.path("a"))
    a.add("a" => "a content").commit("added a file")
    
    b = a.clone(method_root.path("b"))
    assert_equal "a content", b["a"]
    
    a.add("a" => "A content").commit("updated file")
    assert_equal "a content", b["a"]
  
    b.pull
    assert_equal "A content", b["a"]
  end
  
  def test_bare_clone_pulls_from_origin
    a = Git.init(method_root.path("a.git"))
    a.add("a" => "a content").commit("added a file")
    
    b = a.clone(method_root.path("b.git"), :bare => true)
    assert_equal "a content", b["a"]
    
    a.add("a" => "A content").commit("updated file")
    assert_equal "a content", b["a"]
    
    b.pull
    assert_equal "A content", b["a"]
  end
  
  def test_clone_and_pull_in_a_custom_env
    FileUtils.mkdir_p(method_root.path)
    
    git_dir = method_root.path("c.git")
    work_tree = method_root.path("d")
    index_file = method_root.path("e")
    `GIT_DIR='#{git_dir}' git init --bare`
    
    current_env = {}
    ENV.each_pair do |key, value|
      current_env[key] = value
    end
    
    begin
      ENV['GIT_DIR'] = git_dir
      ENV['GIT_WORK_TREE'] = work_tree
      ENV['GIT_INDEX_FILE'] = index_file
      
      a = Git.init(method_root.path("a"))
      a.add("a" => "a content").commit("added a file")
      
      b = a.clone(method_root.path("b"))
      b.add("b" => "b content").commit("added a file")
  
      assert_equal a.branch, b.branch
      assert_equal method_root.path("a/.git"), a.path
      assert_equal method_root.path("b/.git"), b.path
  
      assert_equal "a content", a["a"]
      assert_equal nil, a["b"]
      assert_equal "a content", b["a"]
      assert_equal "b content", b["b"]
    ensure
      ENV.clear
      current_env.each_pair do |key, value|
        ENV[key] = value
      end
    end
  end
  
  #
  # push tests
  #
  
  def test_push_only_pushes_the_specified_branch
    a = Git.init(method_root.path("a"), :is_bare => true)
    
    a.checkout('master')
    initial_master_head = a.add("a" => "a content").commit("added a file")
    
    a.checkout('alt')
    initial_alt_head = a.add("b" => "b content").commit("added a file")
    
    a.checkout('master')
    b = a.clone(method_root.path("b"))
    
    b.checkout('master')
    current_master_head = b.add("c" => "c content").commit("added a file")
    
    b.checkout('alt')
    current_alt_head = b.add("d" => "d content").commit("added a file")
    
    b.checkout('master')
    b.push('origin/master')
    
    assert_equal [current_master_head, initial_alt_head], a.rev_parse('master', 'alt')
  end
  
  def test_push_raises_an_error_if_given_a_non_tracking_branch
    err = assert_raises(RuntimeError) { git.push('master') } 
    assert_equal 'not a tracking branch: "master"', err.message
  end
  
  #
  # pull tests
  #
  
  def test_pull_fast_fowards_when_possible
    a = Git.init(method_root.path("a"))
    a.add("one" => "One").commit("added one")
    
    b = a.clone(method_root.path("b"))
    a.add("two" => "Two").commit("added two")
    
    b.pull
    assert_equal a.head, b.head
  end
  
  def test_pull_merges_changes
    a = Git.init(method_root.path("a"))
    a.add("one" => "One").commit("added one")
    
    b = a.clone(method_root.path("b"))
    a_head = a.add("two" => "Two").commit("added two")
    b_head = b.add("three" => "Three").commit("added three")
    
    b.pull
    commit = b.get(:commit, b.head)
    assert_equal "gitgo merge of origin/gitgo into gitgo", commit.message
    assert_equal [a_head, b_head].sort, commit.parents.collect {|c| c.id }.sort
    
    assert_equal "One", a["one"]
    assert_equal "Two", a["two"]
    assert_equal nil, a["three"]
    
    assert_equal "One", b["one"]
    assert_equal "Two", b["two"]
    assert_equal "Three", b["three"]
  end
  
  def test_pull_does_nothing_unless_necessary
    a = Git.init(method_root.path("a"))
    a.add("a" => "a content").commit("added a file")
    
    b = a.clone(method_root.path("b"))
    
    previous = b.head
    b.pull
    assert_equal previous, b.head
    
    b.add("b" => "b content").commit("added a file")
    
    previous = b.head
    b.pull
    assert_equal previous, b.head
    
    a.add("a" => "A content").commit("updated a file")
    
    previous = b.head
    b.pull
    assert previous != b.head
  end
  
  def test_pull_only_pulls_the_specified_branch
    a = Git.init(method_root.path("a"))
    
    a.checkout('master')
    initial_master_head = a.add("a" => "a content").commit("added a file")
    
    a.checkout('alt')
    initial_alt_head = a.add("b" => "b content").commit("added a file")
    
    a.checkout('master')
    b = a.clone(method_root.path("b"))
    
    a.checkout('master')
    current_master_head = a.add("c" => "c content").commit("added a file")
    
    a.checkout('alt')
    current_alt_head = a.add("d" => "d content").commit("added a file")
    
    b.pull('origin/master')
    assert_equal [current_master_head, initial_alt_head], b.rev_parse('origin/master', 'origin/alt')
  end
  
  def test_pull_raises_an_error_if_given_a_non_tracking_branch
    err = assert_raises(RuntimeError) { git.pull('master') } 
    assert_equal 'not a tracking branch: "master"', err.message
  end
  
  #
  # rev_parse tests
  #
  
  def test_rev_parse_returns_an_array_of_object_refs_parsed_to_their_correct_sha
    setup_repo("simple.git")
    
    assert_equal %w{
      19377b7ec7b83909b8827e52817c53a47db96cf0
      ee9a1ca4441ab2bf937808b26eab784f3d041643
      990191ea92e4dc85f598203e123849df1f8bd124
    }, git.rev_parse("19377b7", "xyz", "xyz^")
  end
  
  def test_rev_parse_returns_empty_array_for_no_inputs
    assert_equal [], git.rev_parse()
  end
  
  def test_rev_parse_raises_error_unless_all_refs_can_be_resolved
    setup_repo("simple.git")
    
    err = assert_raises(RuntimeError) { git.rev_parse("nonexistant") }
    assert_equal "could not resolve to a sha: nonexistant", err.message
    
    not_a_sha = "x" * 40
    err = assert_raises(RuntimeError) { git.rev_parse(not_a_sha) }
    assert_equal "could not resolve to a sha: #{not_a_sha}", err.message
  end
  
  #
  # rev_list tests
  #
  
  def test_rev_list_returns_an_array_of_commits_reachable_from_the_treeishs
    setup_repo("simple.git")
    
    assert_equal %w{
      ee9a1ca4441ab2bf937808b26eab784f3d041643
      19377b7ec7b83909b8827e52817c53a47db96cf0
      990191ea92e4dc85f598203e123849df1f8bd124
      c6746dd1882d772e540342f8e180d3125a9364ad
    }, git.rev_list("19377b7", "xyz")
  end
  
  def test_rev_list_returns_empty_array_for_no_inputs
    assert_equal [], git.rev_list()
  end
  
  #
  # diff_tree test
  #
  
  def test_diff_tree_returns_hash_of_differences
    setup_repo("simple.git")
    
    assert_equal({
      'A' => ['a.txt', 'a/b.txt', 'a/b/c.txt'], 
      'M' => ['one.txt', 'one/two.txt', 'one/two/three.txt'], 
      'D' => []
    }, git.diff_tree('449b55', '19377b'))
    
    assert_equal({
      'A' => [], 
      'M' => [], 
      'D' => ['a.txt', 'a/b.txt', 'a/b/c.txt']
    }, git.diff_tree('7d3db1', '449b55'))
  end
  
  #
  # grep test
  #
  
  def test_grep_yields_path_and_blob_for_blobs_that_match_pattern
    a = git.set(:blob, "a")
    git['one'] = a.to_sym
    
    b = git.set(:blob, "ab")
    git['two'] = b.to_sym
    
    c = git.set(:blob, "abc")
    git['three'] = c.to_sym
    
    sha = git.commit!("created fixture")
    
    results = []
    git.grep("a", sha) {|path, blob| results << [path, blob.id]}
    assert_equal [['one', a], ['two', b], ['three', c]].sort, results.sort
    
    results = []
    git.grep("b", sha) {|path, blob| results << [path, blob.id]}
    assert_equal [['two', b], ['three', c]].sort, results.sort
  end
  
  #
  # tree_grep test
  #
  
  def test_tree_grep_yields_path_and_blob_for_paths_that_match_pattern
    a = git.set(:blob, "a")
    git['one'] = a.to_sym
    
    b = git.set(:blob, "ab")
    git['two'] = b.to_sym
    
    c = git.set(:blob, "abc")
    git['three'] = c.to_sym
    
    sha = git.commit!("created fixture")
    
    results = []
    git.tree_grep("o", sha) {|path, blob| results << [path, blob.id]}
    assert_equal [['one', a], ['two', b]].sort, results.sort
    
    results = []
    git.tree_grep("t[wh]", sha) {|path, blob| results << [path, blob.id]}
    assert_equal [['two', b], ['three', c]].sort, results.sort
  end
  
  #
  # commit_grep test
  #
  
  def test_commit_grep_yields_commit_for_commits_matching_pattern
    if Gitgo::Git.version_ok?
      git['a'] = 'A'
      a = git.commit!("created one")
    
      git['b'] = 'B'
      b = git.commit!("created two")
    
      git['c'] = 'C'
      c = git.commit!("created three")
    
      results = []
      git.commit_grep("o", c) {|commit| results << commit.id }
      assert_equal [a, b].sort, results.sort
    
      results = []
      git.commit_grep("t[wh]", c) {|commit| results << commit.id }
      assert_equal [b, c].sort, results.sort
    end
  end
  
  #
  # stats test
  #
  
  def test_stats_returns_a_hash_of_repo_stats
    stats = git.stats
    assert_equal Hash, stats.class
    assert stats.include?("size")
    assert stats.include?("count")
  end
end