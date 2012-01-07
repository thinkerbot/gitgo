Gitgo
=========

Use the file system to describe the graph.  A separate store will be needed as the graph alone does not reference the update objects:

    A/B (B) # edge, link
    A/B (A) # edge, update
    A/A (A) # vertex, delete
    obj/A

Print the tree to list the graph data. Tsort to order properly.  For each line if file A exists, append B and symlink B to A.  Otherwise create A, write A, and then continue.  Remove all symlinks and the result will be sorted graphs named for each head.  When displaying, these represent each thread or issue.  The files can receive any new edges, but will need to be sorted afterwards.

Use a format similar to a commit for each vertex.

    author name <email> date zone
    tags a b c
    
    summary
    
    body...

Traverse each object and index by name, email, date (day granularity, utc), and tags.  The indexes allow quick searches for activity by a user, or tagged in a particular way.  Tags should include categories like 'issue' or 'page', as applicable.





