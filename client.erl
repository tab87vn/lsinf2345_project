-module (client).
-export ([  disconnect/0,connect/1, 
            start_client/2, client_handler/3,
            message_broadcast/1, message_send/2, 
            group_list/0, group_create/1, group_leave/1, group_join/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% APPLICATION LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

server_node() ->
    % configure server node here
    % maybe let user choose it
    chat_server@localhost.


connect(Username) ->
    % spawn a client process to handle request send to a client once connected
    % global:register_name(client_pid, spawn(chat, start_client, [Username, server_node()])).
    case whereis(client_pid) of 
        undefined ->
            register(client_pid, spawn(client, start_client, [Username, server_node()]));
        _ -> already_logged_on
    end.

%disconnect last connected user
disconnect() ->
    client_pid ! client_disconnect.    


message_broadcast(Msg) ->
    client_pid ! {msg_broadcast, Msg}.


message_send(Username, Msg) ->
    client_pid ! {msg_send, Username, Msg}.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% CHAT ROOM %%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Group infor should also be stored on server/private
group_create(GroupName) ->
    % {GroupName, User_list}
    % % Group_list = [{GroupName, StarterPID GroupUser_list}]
    pass.

group_list() ->
    client_pid ! group_list_req.

group_join(GroupName) ->
    pass.

group_leave(GroupName) ->
    pass.

group_broadcast(GroupName, Message) ->
    %broadcast msg to all ppl in 1 group
    % user can only broadcast to groups that he's joined
    pass.
    

 
% message_send_all(User_list, Msg) ->
%     pass.

    

% broadcast(Username, Pid) ->
%   %self() ! {broadcast, Username, node(), global:whereis_name(client_pid)}.
%   self() ! {broadcast, Username, node(), whereis(client_pid)}.

%broadcast(User_list)
    % if [User|Other_users] -> it's a list, send recursively to all
        % broadcast(User)
        % broadcast(Other_users)
    % if User -> it's just a user, send 1

start_client(Username, ServerNode) ->
    io:format("Hello ~p~n", [Username]),
    {chat_server, ServerNode} ! {self(), connect, Username},
    %broadcast(Username),
    client_handler(Username, [], []).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% APPLICATION LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% a loop process that handles requests from client
% Group_list = [{GroupName, StarterPID GroupUser_list}]
% Maybe there could be another client_handler which has only 1 param (withtout Group_list)
client_handler(Username, User_list, Group_list) ->
    receive     
        {broadcast, _Username, _Node, _Pid} -> % handles the broadcats message
            io:format("broadcast arrived: ~n"),
            % lists:foreach(
            %   fun(X)->
            %       io:format("~w ",[X]) 
            %   end, 
            %   User_list
            % ).
            [{Pid, Node} ! {bc_hello, _Pid, _Node, _Username} || {Pid, Node, Username} <- User_list],               
            client_handler(Username, User_list, Group_list);

        % broadcast receive from server for updated user list
        {bc_receive, Updated_user_list} ->
            % should remove self PID/User name from the list
            lists:keydelete(Username, 2, Updated_user_list),
            io:format("Other online users (updated): ~p~n", [Updated_user_list]),
            client_handler(Username, Updated_user_list, Group_list);

        % broadcast received from other users
        {bc_receive, Message, Sender} ->
            io:format("Broadcast message from ~w: ~p~n", [Sender, Message]),
            client_handler(Username, User_list, Group_list);

        {bc_hello, Pid, Node, Username} -> % receives a hello from other client
            [{Pid, Node, Username} | User_list],
            client_handler(Username, User_list, Group_list);

        {msg_send, RecipientUsn, Msg} ->
            % should be handled by lower layer
            % User_list format: [{Username, Pid, Node}]
            % search for the username in the tuple list
            %io:format("everything is alright!~n"),

            case lists:keysearch(RecipientUsn, 2, User_list) of
                    false -> % nothing found
                        recipient_username_not_found;
                    {value, {RcptPid, RcptUsn}} -> % tuple returned
                        %io:format("Send message ~w to user ~w with pid ~w~n", [Msg, RcptUsn, RcptPid]),
                        RcptPid ! {msg_receive, RcptUsn, Msg, Username, self()}
            end,
            client_handler(Username, User_list, Group_list);

        {msg_broadcast, Msg} ->
            io:format("broadcast requested~n"),
            broadcast(Msg, User_list, Username), % WHY ONLY 1 TIME?
            %[RcptPid ! {bc_receive, Msg, Username} || {RcptPid, RcptUsn} <- User_list],
            client_handler(Username, User_list, Group_list);


        {msg_receive, _RecipientUsn, Msg, SenderUsn, SenderPid} ->
            % when receiving a message sent by another
            io:format("~w: ~p~n", [SenderUsn, Msg]),
            %log system works here to record into Riak later
            client_handler(Username, User_list, Group_list);

        client_connect ->
            pass;

        client_disconnect ->
            {chat_server, server_node()} ! {whereis(Username), client_disconnected},
            unregister(Username);


        group_list_req ->
            io:format("List all avaiable groups on server!"),
            client_handler(Username, User_list, Group_list)
    end.

broadcast(Msg, User_list, Sender) ->
    [Pid ! {bc_receive, Msg, Sender} || {Pid, Username} <- User_list].


%%%% ROUTER LAYER %%%%%%%%%
%%% Involve logical dispatching
client_router_layer() ->
    receive
        % Message = {Pid, Usersname}
        {broadcast, Message} -> %send message to all nodes connected
            sent,
            client_link_layer();
        {unicast, Node, Message} -> % send message to 1 specific node
            sent,
            client_link_layer()
    end.

%%% LINK LAYER OF CLIENT
%%% 
client_link_layer() ->
    receive
        % Message = {Pid, Message}, Message = {Username, Node, etc}
        {broadcast, Message} -> %send message to all nodes connected
            sent,
            client_link_layer();
        {unicast, Node, Message} -> % send message to 1 specific node
            sent,
            client_link_layer()
    end.

