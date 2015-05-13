%% ALL THE MESSAGE DISPLAY SHOULD BE DONE ON APPLICATION LAYER

-module (client).
-export ([  disconnect/0,connect/1, 
            start_client/2, client_handler/3,
            message_broadcast/1, message_send/2, 
            group_list/0, group_create/2, group_leave/1, group_join/1, group_broadcast/2]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% APPLICATION LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

server_node() ->
    chat_server@localhost.


connect(Username) ->
    % spawn a client process to handle request send to a client once connected
    % global:register_name(client_pid, spawn(chat, start_client, [Username, server_node()])).
    case whereis(client_pid) of 
        undefined ->
            register(client_pid, spawn(client, start_client, [Username, server_node()]));
            %register()
        _ -> already_logged_on
    end.

%disconnect last connected user
disconnect() ->
    client_pid ! client_disconnect.    


message_broadcast(Msg) ->
    client_pid ! {msg_broadcast, Msg}.


message_send(Username, Msg) ->
    client_pid ! {msg_send, Username, Msg}.


group_create(Name, Description) ->
    client_pid ! {group_create_req, Name, Description}.
    
group_list() ->
    client_pid ! group_list_req.

group_list_active() ->
    client_pid ! group_list_active_req.

group_join(GroupName) ->
    client_pid ! {group_join_req, GroupName}.

group_leave(GroupName) ->
    client_pid ! {group_leave_req, GroupName}.

group_broadcast(GroupName, Message) ->    
    client_pid ! {group_broadcast_req, GroupName, Message}.

    start_client(Username, ServerNode) ->
    io:format("Hello ~p~n", [Username]),
    {chat_server, ServerNode} ! {self(), connect, Username},
    %broadcast(Username),
    client_handler(Username, [], []).
    

 
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




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% CONTROLLER LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% a loop process that handles requests from client
% Group_list = [{GroupName, StarterPID GroupUser_list}]
% Maybe there could be another client_handler which has only 1 param (withtout Group_list)
client_handler(Username, UserList, Group_list) ->
    receive     
        {broadcast, _Username, _Node, _Pid} -> % handles the broadcats message
            io:format("broadcast arrived: ~n"),
             [{Pid, Node} ! {bc_hello, _Pid, _Node, _Username} || {Pid, Node, Username} <- UserList],               
            client_handler(Username, UserList, Group_list);

        % broadcast receive from server for updated user list
        {bc_receive, BroadcastMsg} ->
            % should remove self PID/User name from the list
            case BroadcastMsg of
                {updated_user_list, UpdatedUserList} ->
                    lists:keydelete(Username, 2, UpdatedUserList),
                    io:format("Current online user(s): ~p~n", [UpdatedUserList]),
                    client_handler(Username, UpdatedUserList, Group_list);
                {updated_group_list, UpdatedGroupList} ->
                    io:format("Available group chat: ~p~n", [UpdatedGroupList]),
                    client_handler(Username, UserList, UpdatedGroupList);
                {updated_group_member_join, NewMember} ->
                    io:format("~p just joined the conversation~n", [NewMember]);
                {updated_group_member_leave, Username} ->
                    io:format("~p just left the conversation~n", [Username]);
                _ ->
                    unknown_broadcast_message
            end;

        % broadcast received from other users
        {bc_receive, Message, Sender} ->
            io:format("Broadcast message from ~w: ~p~n", [Sender, Message]),
            client_handler(Username, UserList, Group_list);

        {msg_send, RecipientUsn, Msg} ->
            % should be handled by lower layer
            % User_list format: [{Username, Pid, Node}]
            % search for the username in the tuple list
            %io:format("everything is alright!~n"),

            case lists:keysearch(RecipientUsn, 2, UserList) of
                false -> % nothing found
                    recipient_username_not_found;
                {value, {RcptPid, RcptUsn}} -> % tuple returned
                    %io:format("Send message ~w to user ~w with pid ~w~n", [Msg, RcptUsn, RcptPid]),
                    RcptPid ! {msg_receive, RcptUsn, Msg, Username, self()}
            end,
            client_handler(Username, UserList, Group_list);

        {msg_broadcast, Msg} ->
            io:format("broadcast requested~n"),
            broadcast(Msg, UserList, Username), % WHY ONLY 1 TIME?
            %[RcptPid ! {bc_receive, Msg, Username} || {RcptPid, RcptUsn} <- User_list],
            client_handler(Username, UserList, Group_list);


        {msg_receive, _RecipientUsn, Msg, SenderUsn, SenderPid} ->
            % when receiving a message sent by another
            io:format("~w: ~p~n", [SenderUsn, Msg]),
            %log system works here to record into Riak later
            client_handler(Username, UserList, Group_list);

        % TODO: seperate from application layer
        client_connect ->
            pass;

        client_disconnect ->
            {chat_server, server_node()} ! {self(), client_disconnected},
            unregister(client_pid);

        %%%%%%%%%%% GROUP %%%%%%%%%%%%%
        % request to create group (group name, description)
        {group_create_req, GroupName, GroupDescription} ->
            {group_server, server_node()} ! {group_create_req, GroupName, GroupDescription, Username, self()},
            client_handler(Username, UserList, Group_list);

        {group_create_res, GroupName, UpdatedGroupList} ->
            % print out the name
            io:format("Group ~p has been created!~n", [GroupName]),
            io:format("Available chat groups: ~p~n", [UpdatedGroupList]),
            client_handler(Username, UserList, Group_list);

        % request to join an existing group
        {group_join_req, GroupName} ->
            {group_server, server_node()} ! {group_join_req, GroupName, Username, self()},
            client_handler(Username, UserList, Group_list);

        %
        {group_join_res, UpdatedGroupList, [NewMember|Others]} ->
            io:format("Updated group info: ~p~n", UpdatedGroupList),            
            BCMessage = {updated_group_member, NewMember},
            broadcast(BCMessage, Others),
            client_handler(Username, UserList, Group_list);            


        % request to leave an existing group of which one is member
        {group_leave_req, GroupName} ->
            {group_server, server_node()} ! {group_leave_req, GroupName, Username, self()},
            client_handler(Username, UserList, Group_list);

        {group_leave_res, UpdatedGroupList, UpdatedMemberList, Username} ->
            BCMessage = {updated_group_member, Username},
            broadcast(BCMessage, UpdatedMemberList),
            client_handler(Username, UserList, Group_list);

        group_list_req ->
            % io:format("Available groups: ~p~n!", [Group_list]),
            % client_handler(Username, User_list, Group_list)
            {group_server, server_node()} ! {group_list_req, self()},
            client_handler(Username, UserList, Group_list);

        {group_list_rest, Message} ->
            io:format("Available chat groups: ~n", [Message]),
            client_handler(Username, UserList, Group_list);

        {group_broadcast_req, GroupName, Message} ->
            case lists:keysearch(GroupName, 1, Group_list) of
                false ->
                    no_such_group,
                    client_handler(Username, UserList, Group_list);
                {value, {Name, Desc, Starter, MemberList}} ->
                    broadcast(Message, MemberList, Username),            
                    client_handler(Username, UserList, Group_list)
            end
            

    end.

broadcast(Msg, User_list, Sender) ->
    [Pid ! {bc_receive, Msg, Sender} || {Pid, Username} <- User_list].
broadcast(Msg, User_list) ->
    [Pid ! {bc_receive, Msg} || {Pid, Username} <- User_list].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ROUTER LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TRANSMIT LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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

