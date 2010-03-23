describe 'Gitgo.Graph'
  describe '.node'
    it 'should return the a node with the graph attributs'
      var element = $(fixture('fork')).find('li');
      var node = Gitgo.Graph.node(element);
      
      node.x.should.be(0);
      node.y.should.be(1);
      node.current.should.eql([]);
      node.transitions.should.eql([0, 1, 2]);
    end
    
    it 'should record the element id'
      var element = $(fixture('fork')).find('li');
      var node = Gitgo.Graph.node(element)
      
      node.id.should.be(element.attr('id'));
    end
  end
end