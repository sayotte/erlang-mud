-module(trie).
-export([new/0, delete/1, add_term/3, lookup_term/2]).
% -compile(export_all).
-record(trie_node,
        {name = "",
         value = undefined}).

new() ->
    G = digraph:new([acyclic]),
    V = digraph:add_vertex(G),
    digraph:add_vertex(G, V, #trie_node{name="", value=undefined}),
    {G, V}.

delete(Trie) ->
    {Digraph, _} = Trie,
    digraph:delete(Digraph).

lookup_term(Trie, Term) ->
    {G, Root} = Trie,
    case get_ideal_vertex(G, Term, Root) of
        undefined ->
            undefined;
        Vertex ->
            {_, Label} = digraph:vertex(G, Vertex),
            Label#trie_node.value
    end.

add_term(Trie, Term, Value) ->
    {Graph, Root} = Trie,
    ParentVertex = get_best_vertex_for_insertion(Graph, Term, Root),
    ChildVertex = add_child_vertex(Graph, Term, ParentVertex, Value),
    ChildVertex.

get_best_vertex_for_insertion(Graph, Term, Root) ->
    % Find the best vertex to add this term to
    BestVertex = get_best_vertex(Graph, Term, Root),
    {_, BestLabel} = digraph:vertex(Graph, BestVertex),
    if
        % If this is the root node we're done; we can insert below immediately
        BestVertex == Root ->
            BestVertex;
        % If this is not the root node we MAY need to insert a new node containing
        % our common characters first, then add ours to that.
        true ->
            % Determine how many characters we have in common
            MatchLen = string_match_len(Term, BestLabel#trie_node.name),
            BestLabelNameLen = length(BestLabel#trie_node.name),
            if
                % If it matches all characters in the current vertex, it should
                %   just be a child
                MatchLen == BestLabelNameLen ->
                    BestVertex;
                % Otherwise we need to insert an intermediate vertex
                true ->
                    CommonString = lists:sublist(BestLabel#trie_node.name, MatchLen),
                    IntermediateVertex = insert_intermediate_vertex(Graph, CommonString, BestVertex),
                    IntermediateVertex
            end
    end.

insert_intermediate_vertex(Graph, CommonString, OldVertex) ->
    % Collect info about the edge between the parent / existing vertex
    [OldEdge|_] = digraph:in_edges(Graph, OldVertex),
    % We'll re-use the old label for the edge between the parent / new vertices
    {_,ParentVertex,_,OldEdgeLabel} = digraph:edge(Graph, OldEdge),
    % Prep a new label for the edge between the new / existing vertices
    {_,OldVertexLabel} = digraph:vertex(Graph, OldVertex),
    NewEdgeLabel = [lists:nth(length(CommonString) + 1,
                             OldVertexLabel#trie_node.name)],
    % Add the new vertex
    NewVertex = digraph:add_vertex(Graph),
    digraph:add_vertex(Graph, NewVertex, #trie_node{name=CommonString,
                                                    value=undefined}),
    % Unlink the parent / old vertices
    digraph:del_edge(Graph, OldEdge),
    % Link the parent / new vertices
    digraph:add_edge(Graph, ParentVertex, NewVertex, OldEdgeLabel),
    % Link the new / old vertices
    digraph:add_edge(Graph, NewVertex, OldVertex, NewEdgeLabel),

    NewVertex.

add_child_vertex(Graph, Name, ParentVertex, Value) ->
    % Create the child vertex itself
    ChildVertex = digraph:add_vertex(Graph),
    digraph:add_vertex(Graph, ChildVertex, #trie_node{name=Name,
                                                      value=Value}),
    % Grab the parent's label; we need its name to determine the label for
    %   the edge leading to the new child
    {_,ParentVertexLabel} = digraph:vertex(Graph, ParentVertex),
    % Label for the new edge is the first character character in the name of
    %   the new vertex which is unique from the name of the parent vertex
    NewEdgeLabel = [lists:nth(length(ParentVertexLabel#trie_node.name) + 1,
                             Name)],
    digraph:add_edge(Graph, ParentVertex, ChildVertex, NewEdgeLabel),
    ChildVertex.

% Returns a vertex
% If necessary due to lack of matches, this will be the root vertex
get_best_vertex(Graph, String, Vertex) ->
    case get_better_vertex(Graph, String, Vertex) of
        % false means 'there is no better vertex, this one is good'
        false ->
            Vertex;
        % false means 'there is no better vertex, this one is good'
        undefined ->
            Vertex;
        % false means 'there is no better vertex, this one is good'
        NextVertex ->
            get_best_vertex(Graph, String, NextVertex)
    end.

% Returns either a vertex or undefined
% Undefined is guaranteed to be returned if there is no matching or unambiguously described term in the trie
get_ideal_vertex(_, String, Vertex) when (String == []) ->
    Vertex;
get_ideal_vertex(Graph, String, Vertex) ->
    case get_better_vertex(Graph, String, Vertex) of
        % false means 'there is no better vertex, this one is good'
        false ->
            Vertex;
        % false means 'there is no better vertex, this one is good'
        undefined ->
            undefined;
        % false means 'there is no better vertex, this one is good'
        NextVertex ->
            get_ideal_vertex(Graph, String, NextVertex)
    end.
% Returns one of:
%           -   a vertex
%           -   false (meaning the vertex supplied is the best available)
%           -   undefined (meaning there is no acceptable vertex, including
%                   the one supplied
get_better_vertex(Graph, String, Vertex) ->
    {_, Label} = digraph:vertex(Graph, Vertex),
    StringLen = length(String),
    NameLen = length(Label#trie_node.name),
    if
        NameLen > StringLen ->
            MatchLen = string_match_len(Label#trie_node.name, String),
            if
                % Example: V="foo", S="fe" -> undefined
                MatchLen < StringLen ->
                    undefined;
                % Example: V="foo", S="fo" -> false
                true ->
                    false
            end;
        NameLen == StringLen ->
            Comp = (String == Label#trie_node.name),
            case Comp of
                % Example: V="foo", S="foo" -> false
                true ->
                    false;
                % Example: V="foo", S="fee" -> undefined
                false ->
                    undefined
            end;
        NameLen < StringLen ->
            MatchLen = string_match_len(Label#trie_node.name, String),
            if
                % Example: V="foo", S="feeee" -> undefined
                MatchLen < NameLen ->
                    undefined;
                % Example: V="foo", S="foobar" -> V(foob)
                true ->
                    Edges = digraph:out_edges(Graph, Vertex),
                    Term = lists:nth(NameLen + 1, String),
                    case get_best_edge(Graph, Edges, Term) of
                        false ->
                            undefined;
                        BestEdge ->
                            {_,_,NextVertex,_} = digraph:edge(Graph, BestEdge),
                            NextVertex
                    end
            end
    end.
get_best_edge(_, Edges, _) when (Edges == []) ->
    false;
get_best_edge(Graph, Edges, Term) ->
    [Head|Tail] = Edges,
    {_,_,_,Label} = digraph:edge(Graph, Head),
    case Label == [Term] of
        true ->
            Head;
        false ->
            get_best_edge(Graph, Tail, Term)
    end.

string_match_len(String1, String2) ->
    string_match_len(String1, String2, 1).
string_match_len(String1, String2, Index) ->
    InBounds = string_match_len_in_bounds(String1, String2, Index),
    case InBounds of
        false ->
            Index - 1;
        true ->
            Comp = (lists:nth(Index, String1) == lists:nth(Index, String2)),
            case Comp of
                true ->
                    string_match_len(String1, String2, Index + 1);
                false ->
                    Index - 1
            end
    end.
string_match_len_in_bounds(String1, String2, Len) ->
    Length1 = length(String1),
    Length2 = length(String2),
    if
        Len > Length1; Len > Length2 ->
            false;
        true ->
            true
    end.

% % This sample set is useful for testing the lookup routines.
% % ''
% %   g->get
% %   l->
% %       a->
% %           s->last
% %           t->later
% %       o->look
% build_example_trie() ->
%     {G, Root} = new(),
%     Get = digraph:add_vertex(G),
%     digraph:add_vertex(G, Get, #trie_node{name="get", value=get}),
%     digraph:add_edge(G, Root, Get, "g"),
% 
%     L = digraph:add_vertex(G),
%     digraph:add_vertex(G, L, #trie_node{name="l"}),
%     digraph:add_edge(G, Root, L, "l"),
% 
%     La = digraph:add_vertex(G),
%     digraph:add_vertex(G, La, #trie_node{name="la"}),
%     digraph:add_edge(G, L, La, "a"),
% 
%     Last = digraph:add_vertex(G),
%     digraph:add_vertex(G, Last, #trie_node{name="lasting", value=lasting}),
%     digraph:add_edge(G, La, Last, "s"),
% 
%     Later = digraph:add_vertex(G),
%     digraph:add_vertex(G, Later, #trie_node{name="later", value=later}),
%     digraph:add_edge(G, La, Later, "t"),
% 
%     Look = digraph:add_vertex(G),
%     digraph:add_vertex(G, Look, #trie_node{name="look", value=look}),
%     digraph:add_edge(G, L, Look, "o"),
% 
%     Super = digraph:add_vertex(G),
%     digraph:add_vertex(G, Super, #trie_node{name="super", value=super}),
%     digraph:add_edge(G, Root, Super, "s"),
% 
%     Superstrong = digraph:add_vertex(G),
%     digraph:add_vertex(G, Superstrong, #trie_node{name="superstrong", value=superstrong}),
%     digraph:add_edge(G, Super, Superstrong, "s"),
% 
%     {G, Root}.
% % This sample set is useful for testing the insertion routines.
% % ''
% %   g->get
% %   l->
% %       a->
% %           s->last
% %           t->later
% %       o->look
% %           e->looker
% %               t->lookerthar
% %   s->super
% %       s->superstrong
% build_example_trie2() ->
%     Trie = new(),
%     add_term(Trie, "get", getval),
%     add_term(Trie, "lasting", lastingval),
%     add_term(Trie, "later", laterval),
%     add_term(Trie, "look", lookval),
%     add_term(Trie, "looker", lookerval),
%     add_term(Trie, "lookerthar", lookertharval),
%     add_term(Trie, "super", superval),
%     add_term(Trie, "superstrong", superstrong),
%     Trie.
