Gitgo
=========

Storage
---------

Use the file system to describe the graph:

    0/A (A) # vertex -- so each object is stored at least once
    A/B (B) # edge, link
    A/B (A) # edge, update
    A/A (A) # vertex, delete

Print the tree to list the graph data. Tsort to order properly.  For each line if file A exists, append "A/B" and symlink B to A.  Otherwise create A, write A, and then continue.  For 0, append "A" (the all index).  Remove all symlinks and the result will be sorted graphs named for each head.  When displaying, these represent each thread or issue.  The files can receive any new edges, but will need to be sorted afterwards.

Use a format similar to a commit for each vertex.

    author name <email> date zone
    tags a b c
    
    summary
    
    body...

Searches
---------

Traverse each object and index by name, email, date (day granularity, utc), and tags.  The indexes allow quick searches for activity by a user, or tagged in a particular way.  Tags should include categories like 'issue' or 'page', as applicable.  The indexes are files of shas, separated by lines.

To search for:

* A category - list all heads and find common lines (comm)
* Activity   - grep index for input
* Heads      - grep head files for sha

Combine searches as needed to get the desired results.

Display
---------

A summary of a thread can be seen by listing the head with the summary lines, much like a git-graph --oneline.  In fact you might be able to literally store objects as commits and just use that.  That would be pretty bad-ass.  You could translate each head into a branch, in a separate gitgo/git repo.  To add/update, you would commit to the issue branch and add to the gitgo branch.

For when you want to only see the latest, you need to filter updates and deletes.  These unfortunately would have to be separate branches themselves.  And when you update/delete, the filter branch would have to be recreated.  Like a rebase.

Update:

    A/B  (B)
    B/B1 (B)

* replace A/B with A/B1
* delete line B/B1

Delete:

    A/A (A)

* replace x/A with x/x

This rule includes the A/A line - A is now a separate vertex, still accessible if desired but identifiable as a detached head because it has no head file.
