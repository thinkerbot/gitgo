require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/controllers/code'

class CodeTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  attr_reader :repo
  
  def setup
    super
    @repo = Gitgo::Repo.new(setup_repo("simple.git"))
    app.set :repo, @repo
    app.instance_variable_set :@prototype, nil
  end
  
  def app
    Gitgo::Controllers::Code
  end
  
  #
  # blob test
  #

  def test_get_blob_shows_contents_for_blob
    # by ref
    get("/blob/xyz/x.txt")
    assert last_response.body.include?('ee9a1ca4441ab2bf937808b26eab784f3d041643')
    assert last_response.body.include?('added files x, y, and z')
    assert last_response.body.include?('Contents of file x.')

    # by sha
    get("/blob/7d3db1d8b487a098e9f5bca17c21c668d800f749/a/b.txt")
    assert last_response.body.include?('7d3db1d8b487a098e9f5bca17c21c668d800f749')
    assert last_response.body.include?('changed contents of a, b, and c')
    assert last_response.body.include?('Contents of file B.')

    # by tag
    get("/blob/only-123/one/two/three.txt")
    assert last_response.body.include?('449b5502e8dc49264d862b4fc0c01ba115fc9f82')
    assert last_response.body.include?('removed files a, b, and c')
    assert last_response.body.include?('Contents of file three.')
  end

  def test_get_blob_greps_for_blobs_at_specified_commit
    get("/blob", :pattern => 'file', 'at' => '7d3db1d8b487a098e9f5bca17c21c668d800f749')
    assert last_response.body.include?('a/b/c.txt')
    assert !last_response.body.include?('x/y/z.txt')

    get("/blob", :pattern => 'file', 'at' => 'a1aafafbb5f74fb48312afedb658569b00f4a796')
    assert !last_response.body.include?('a/b/c.txt')
    assert last_response.body.include?('x/y/z.txt')
  end

  #
  # tree test
  #

  def test_get_tree_shows_linked_tree_contents_for_commit
    # by ref
    get("/tree/xyz")
    assert last_response.body.include?('ee9a1ca4441ab2bf937808b26eab784f3d041643')
    assert last_response.body.include?('added files x, y, and z')
    %w{
      /blob/xyz/a.txt
      /tree/xyz/a
      /blob/xyz/one.txt
      /tree/xyz/one
      /blob/xyz/x.txt
      /tree/xyz/x
    }.each do |link|
      assert last_response.body.include?(link)
    end

    # by sha
    get("/tree/7d3db1d8b487a098e9f5bca17c21c668d800f749/a")
    assert last_response.body.include?('7d3db1d8b487a098e9f5bca17c21c668d800f749')
    assert last_response.body.include?('changed contents of a, b, and c')
    %w{
      /blob/7d3db1d8b487a098e9f5bca17c21c668d800f749/a/b.txt
      /tree/7d3db1d8b487a098e9f5bca17c21c668d800f749/a/b
    }.each do |link|
      assert last_response.body.include?(link)
    end

    # by tag
    get("/tree/only-123/one/two")
    assert last_response.body.include?('449b5502e8dc49264d862b4fc0c01ba115fc9f82')
    assert last_response.body.include?('removed files a, b, and c')
    %w{
      /blob/only-123/one/two/three.txt
    }.each do |link|
      assert last_response.body.include?(link)
    end
  end

  def test_get_tree_greps_paths_at_specified_commit
    get("/tree", :pattern => 'txt', 'at' => '7d3db1d8b487a098e9f5bca17c21c668d800f749')
    assert last_response.body.include?('a/b/c.txt')
    assert !last_response.body.include?('x/y/z.txt')

    get("/tree", :pattern => 'txt', 'at' => 'a1aafafbb5f74fb48312afedb658569b00f4a796')
    assert !last_response.body.include?('a/b/c.txt')
    assert last_response.body.include?('x/y/z.txt')
  end

  #
  # commit test
  #

  def test_get_commit_shows_diff
    # by ref
    get("/commit/xyz")
    assert last_response.ok?
    assert last_response.body.include?('ee9a1ca4441ab2bf937808b26eab784f3d041643')
    assert last_response.body.include?('added files x, y, and z')
    assert last_response.body.include?('<li class="add">x.txt</li>')

    # by sha
    get("/commit/e9b525ed0dfde2833001173e7f185939b46b0274")
    assert last_response.ok?
    assert last_response.body.include?('e9b525ed0dfde2833001173e7f185939b46b0274')
    assert last_response.body.include?('<li class="add">alpha.txt</li>')
    assert last_response.body.include?('<li class="rm">one.txt</li>')

    diff = %q{--- a/x.txt
+++ b/x.txt
@@ -1 +1 @@
-Contents of file x.
\ No newline at end of file
+Contents of file X.
\ No newline at end of file}

    assert last_response.body.include?(diff)
  end

  def test_get_commit_greps_commits
    get("/commit", :grep => 'added')
    assert last_response.body.include?('added files x, y, and z')
    assert !last_response.body.include?('removed files a, b, and c')

    get("/commit", :grep => 'removed')
    assert !last_response.body.include?('added files x, y, and z')
    assert last_response.body.include?('removed files a, b, and c')
  end

  #
  # obj test
  #

  def test_get_obj_shows_object_and_comments
    # blob
    get("/obj/c9036dc2e34776218519a95470bd1dce1b47ac9a")
    assert last_response.body.include?('c9036dc2e34776218519a95470bd1dce1b47ac9a')
    assert last_response.body.include?('Contents of file x.'), last_response.body

    # tree
    get("/obj/42dd6245f1dfd6f5c4fcbe62bb86b79d89f539cc")
    assert last_response.body.include?('42dd6245f1dfd6f5c4fcbe62bb86b79d89f539cc')
    assert last_response.body.include?('<a href="/obj/d6b80e9b86f052fef9f495446fdf7bdebd8a5b7e">y.txt</a>')
    assert last_response.body.include?('<a href="/obj/8f7de8797365eefbac8abeff9b9e78130122fcc2">y</a>')

    # commit
    get("/obj/ee9a1ca4441ab2bf937808b26eab784f3d041643")
    assert last_response.body.include?('ee9a1ca4441ab2bf937808b26eab784f3d041643')
    assert last_response.body.include?('added files x, y, and z')

    # # tag
    # get("/obj/d0ad2534e98f0a2b9573af0355d7371468eb77f1")
    # assert last_response.body.include?('d0ad2534e98f0a2b9573af0355d7371468eb77f1')
    # assert last_response.body.include?('tag of project with one, two, three only'), last_response.body
  end

  def test_obj_returns_pretty_print_content_if_specified
    # blob
    get("/obj/c9036dc2e34776218519a95470bd1dce1b47ac9a", :content => true)
    assert_equal "text/plain", last_response['Content-Type']
    assert_equal "Contents of file x.", last_response.body

    # tree
    get("/obj/42dd6245f1dfd6f5c4fcbe62bb86b79d89f539cc", :content => true)
    assert_equal "text/plain", last_response['Content-Type']
    assert_equal "100644 blob d6b80e9b86f052fef9f495446fdf7bdebd8a5b7e\ty.txt\n040000 tree 8f7de8797365eefbac8abeff9b9e78130122fcc2\ty", last_response.body

    # commit
    get("/obj/ee9a1ca4441ab2bf937808b26eab784f3d041643", :content => true)
    assert_equal "text/plain", last_response['Content-Type']
    assert_equal %q{tree 71719943af3c7a12804c1a9946913392cac3a55e
parent 990191ea92e4dc85f598203e123849df1f8bd124
author Simon Chiang <simon.chiang@pinnacol.com> 1255115805 -0600
committer Simon Chiang <simon.chiang@pinnacol.com> 1255115805 -0600

added files x, y, and z
}, last_response.body

    # tag
    get("/obj/d0ad2534e98f0a2b9573af0355d7371468eb77f1", :content => true)
    assert_equal "text/plain", last_response['Content-Type']
    assert_equal %q{object 449b5502e8dc49264d862b4fc0c01ba115fc9f82
type commit
tag only-123
tagger Simon Chiang <simon.chiang@pinnacol.com> 1255115917 -0600

tag of project with one, two, three only
}, last_response.body
  end

  def test_obj_downloads_true_raw_data_if_specified
    # blob
    get("/obj/c9036dc2e34776218519a95470bd1dce1b47ac9a", :download => true)
    assert_equal "text/plain", last_response['Content-Type']
    assert_equal "blob 19\000Contents of file x.", last_response.body
    assert_equal "c9036dc2e34776218519a95470bd1dce1b47ac9a", Digest::SHA1.hexdigest(last_response.body)

    # tree
    get("/obj/42dd6245f1dfd6f5c4fcbe62bb86b79d89f539cc", :download => true)
    assert_equal "text/plain", last_response['Content-Type']
    assert_equal "tree 61\000100644 y.txt\000\326\270\016\233\206\360R\376\371\364\225Do\337{\336\275\212[~40000 y\000\217}\350yse\356\373\254\212\276\377\233\236x\023\001\"\374\302", last_response.body
    assert_equal "42dd6245f1dfd6f5c4fcbe62bb86b79d89f539cc", Digest::SHA1.hexdigest(last_response.body)

    # commit
    get("/obj/ee9a1ca4441ab2bf937808b26eab784f3d041643", :download => true)
    assert_equal "text/plain", last_response['Content-Type']
    assert_equal %Q{commit 252\000tree 71719943af3c7a12804c1a9946913392cac3a55e
parent 990191ea92e4dc85f598203e123849df1f8bd124
author Simon Chiang <simon.chiang@pinnacol.com> 1255115805 -0600
committer Simon Chiang <simon.chiang@pinnacol.com> 1255115805 -0600

added files x, y, and z
}, last_response.body
    assert_equal "ee9a1ca4441ab2bf937808b26eab784f3d041643", Digest::SHA1.hexdigest(last_response.body)

    # tag
    get("/obj/d0ad2534e98f0a2b9573af0355d7371468eb77f1", :download => true)
    assert_equal "text/plain", last_response['Content-Type']
    assert_equal %Q{tag 180\000object 449b5502e8dc49264d862b4fc0c01ba115fc9f82
type commit
tag only-123
tagger Simon Chiang <simon.chiang@pinnacol.com> 1255115917 -0600

tag of project with one, two, three only
}, last_response.body
    assert_equal "d0ad2534e98f0a2b9573af0355d7371468eb77f1", Digest::SHA1.hexdigest(last_response.body)
  end
    
  #
  # post test
  #
  
  def test_post_comments_creates_comment_on_parent
    post("/comments/ee9a1ca4441ab2bf937808b26eab784f3d041643", "content" => "comment content", "commit" => "true")
    assert last_response.redirect?
    
    comment = File.basename(last_response['Location'])
    doc = repo.read(comment)
    
    assert_equal "comment content", doc.content
    assert_equal 'ee9a1ca4441ab2bf937808b26eab784f3d041643', doc['re']
    assert_equal [comment], repo.children('ee9a1ca4441ab2bf937808b26eab784f3d041643')
  end
  
  def test_post_links_comment_to_parent_comment
    post("/comments/ee9a1ca4441ab2bf937808b26eab784f3d041643", "content" => "comment a", "commit" => "true")
    assert last_response.redirect?
    a = File.basename(last_response['Location'])
    
    post("/comments/ee9a1ca4441ab2bf937808b26eab784f3d041643", "content" => "comment b", "parent" => a, "commit" => "true")
    assert last_response.redirect?
    b = File.basename(last_response['Location'])
    
    assert_equal [a], repo.children('ee9a1ca4441ab2bf937808b26eab784f3d041643')
    assert_equal [b], repo.children(a)
  end
  
  def test_post_validates_parent_is_regarding_the_same_object
    post("/comments/ee9a1ca4441ab2bf937808b26eab784f3d041643", "content" => "comment a", "commit" => "true")
    assert last_response.redirect?
    a = File.basename(last_response['Location'])
    
    post("/comments/d0ad2534e98f0a2b9573af0355d7371468eb77f1", "content" => "comment b", "parent" => a, "commit" => "true")
    assert !last_response.ok?
    assert last_response.body.include?("invalid parent for comment on d0ad2534e98f0a2b9573af0355d7371468eb77f1: #{a}")
  end
  
  #
  # put test
  #
  
  def new_comment(content, parent=nil, obj='ee9a1ca4441ab2bf937808b26eab784f3d041643')
    params = {"content" => content, "commit" => "true"}
    params['parent'] = parent if parent
    
    post("/comments/#{obj}", params)
    assert last_response.redirect?
    File.basename(last_response['Location'])
  end
  
  def test_put_replaces_previous_comment_with_new_comment_on_parent
    a = new_comment("comment a")
    b = new_comment("comment b", a)
    c = new_comment("comment c", b)
    
    assert_equal [a], repo.children('ee9a1ca4441ab2bf937808b26eab784f3d041643')
    assert_equal [b], repo.children(a)
    assert_equal [c], repo.children(b)
    
    put("/comments/ee9a1ca4441ab2bf937808b26eab784f3d041643/#{b}", "content" => "comment d", "commit" => "true")
    assert last_response.redirect?
    d = File.basename(last_response['Location'])
    
    doc = repo.read(d)
    assert_equal "comment d", doc.content
    assert_equal 'ee9a1ca4441ab2bf937808b26eab784f3d041643', doc['re']
    
    assert_equal [a], repo.children('ee9a1ca4441ab2bf937808b26eab784f3d041643')
    assert_equal [d], repo.children(a)
    assert_equal [c], repo.children(d)
  end
  
  def test_put_validates_it_is_updating_a_comment_on_the_obj
    put("/comments/ee9a1ca4441ab2bf937808b26eab784f3d041643/d0ad2534e98f0a2b9573af0355d7371468eb77f1", "content" => "update", "commit" => "true")
    assert !last_response.ok?
    assert last_response.body.include?("unknown comment: d0ad2534e98f0a2b9573af0355d7371468eb77f1")
    
    a = new_comment("comment a")
    put("/comments/d0ad2534e98f0a2b9573af0355d7371468eb77f1/#{a}", "content" => "update", "commit" => "true")
    assert !last_response.ok?
    assert last_response.body.include?("not a comment on d0ad2534e98f0a2b9573af0355d7371468eb77f1: #{a}"), last_response.body
    
    b = repo.create("not a comment")
    put("/comments/ee9a1ca4441ab2bf937808b26eab784f3d041643/#{b}", "content" => "update", "commit" => "true")
    assert !last_response.ok?
    assert last_response.body.include?("not a comment: #{b}")
  end
  
  #
  # destroy test
  #
  
  def test_destroy_removes_comment_and_reassignas_children_to_parent
    a = new_comment("comment a")
    b = new_comment("comment b", a)
    c = new_comment("comment c", b)

    assert_equal [b], repo.children(a)
    assert_equal [c], repo.children(b)
  
    delete("/comments/ee9a1ca4441ab2bf937808b26eab784f3d041643/#{b}", "commit" => "true")
    assert last_response.redirect?, last_response.body
  
    assert_equal [c], repo.children(a)
  end
end