-module (server).
-export ([start_server/0, server_run/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%% SERVER SIDE %%%%%%%%%%%%%%%%%%%%%%%%%%%%


start_server() -> % start chat server
	register(chat_server, spawn(server, server_run, [[]])).

%%% Server should maintain the list of online user
server_run(User_list) ->
	receive
		% receive a connect request from client
		{From, connect, Name} ->
            Updated_user_list = server_logon(From, Name, User_list),
            io:format("User ~w signed in!~n", [Name]),
            io:format("Current online user(s): ~p~n", [Updated_user_list]),
            % broadcast an updated online user list 
            broadcast(Updated_user_list, Updated_user_list),
            %[Pid ! {bc_receive, Updated_user_list} || {Pid, Username} <- Updated_user_list],
            server_run(Updated_user_list);

         % receives a disconnect request from client
        {From, client_disconnected} ->
            Updated_user_list = server_logoff(From, User_list),
            io:format("User ~w signed out!~n", [From]),
            io:format("Current online user(s): ~p~n", [Updated_user_list]),
            broadcast(Updated_user_list, Updated_user_list),
            %[Pid ! {bc_receive, Updated_user_list} || {Pid, Username} <- Updated_user_list],
            server_run(Updated_user_list)
	end.

server_logon(SenderPid, Username, User_list) ->
    %% check if logged on anywhere else
    case lists:keymember(Username, 2, User_list) of
        true -> % if the username is already used on other node
            SenderPid ! {messenger, stop, user_exists_at_other_node},  %reject logon
            User_list;
        false ->
            SenderPid! {messenger, logged_on},
            [{SenderPid, Username} | User_list]     %add user to the list
    end.

%%% Server deletes a user from the user list
server_logoff(From, User_List) ->
    lists:keydelete(From, 1, User_List).

broadcast(Msg, User_list) ->
    [Pid ! {bc_receive, Msg} || {Pid, Username} <- User_list].
