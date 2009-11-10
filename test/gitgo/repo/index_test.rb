require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/repo/index'
require 'stringio'

class RepoIndexTest < Test::Unit::TestCase
  Index = Gitgo::Repo::Index
  
  attr_accessor :idx
  
  SHAS = %w{
    dfe0ffed95402aed8420df921852edf6fcba2966
    3a2662fad86206d8562adbf551855c01f248d4a2
    580c31928bc9567075169cacf3e5a03c92514b81
    feff7babf81ab6dae82e2036fe457f0347d74c4f
    0407a96aebf2108e60927545f054a02f20e981ac
  }
  PACKED_SHAS = SHAS.collect {|sha| [sha].pack("H*") }
  
  def setup
    @idx = Index.new StringIO.new
  end
  
  #
  # length test
  #
  
  def test_length_returns_number_of_packed_shas_in_file
    assert_equal 0, idx.length
    
    idx.file << PACKED_SHAS.join
    assert_equal 5, idx.length
  end
  
  #
  # read test
  #
  
  def test_read_reads_n_entries_from_start
    idx.file.string = PACKED_SHAS.join
    
    # in range, subset
    assert_equal SHAS, idx.read
    assert_equal SHAS[0,3], idx.read(3)
    assert_equal SHAS[0,3], idx.read(3, 0)
    assert_equal SHAS[1,2], idx.read(2, 1)
    assert_equal SHAS[0,2], idx.read(2, 0)
    
    # out of range
    assert_equal [], idx.read(2, 6)
    
    idx.file.string = (PACKED_SHAS * 3).join
    
    # in range, maxing out default n
    assert_equal SHAS * 2, idx.read
    assert_equal SHAS * 3, idx.read(nil)
    assert_equal SHAS * 2, idx.read(nil, 5)
  end
  
  #
  # write test
  #
  
  def test_write_writes_entries
    assert_equal [], idx.read
    
    idx.write(SHAS[0]).write(SHAS[1])
    assert_equal [SHAS[0], SHAS[1]], idx.read
    
    idx.file.pos = 0
    idx.write(SHAS[1] + SHAS[0])
    assert_equal [SHAS[1], SHAS[0]], idx.read
  end
  
  #
  # append test
  #
  
  def test_append_appends_an_entry
    assert_equal [], idx.read
    
    idx.append(SHAS[0])
    assert_equal SHAS[0,1], idx.read

    idx.append(SHAS[1])
    assert_equal [SHAS[0], SHAS[1]], idx.read
    
    idx.file.pos = 12
    idx.append(SHAS[0])
    assert_equal [SHAS[0], SHAS[1], SHAS[0]], idx.read
  end
end