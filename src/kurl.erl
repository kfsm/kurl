-module(kurl).

-export([main/1]).

%%
%%
main(Args) ->
   case getopt:parse(opts(), Args) of
      {ok, {_, []}}   ->   
         getopt:usage(opts(), escript:script_name(), "URL"),
         halt(0);
      {ok, {Opts, Urls}} ->
      case lists:member(help, Opts) of
         true ->
            getopt:usage(opts(), escript:script_name(), "URL"),
            halt(0);
         _    ->
            exec(Opts, hd(Urls)),
            halt(0)
      end
   end.

%%
%% command line options
opts() ->
   [
      {help,      $h, "help",    undefined,        "Print usage"}
     ,{verbose,   $v, "verbose", undefined,        "Make the operation more talkative"}
     ,{silent,    $s, "silent",  undefined,        "Silent mode (don't output anything)"}
     ,{trace,     $t, "trace",   undefined,        "Output protocol trace"}
   ].

%%
%%
exec(Opts, Url) ->
   application:ensure_all_started(lager),
   lager:set_loglevel(lager_console_backend, emergency),
   application:ensure_all_started(ssl),
   application:ensure_all_started(knet),
   recv(knet:connect(Url, [{trace, self()}]),  Opts, [os:timestamp()]).

recv(Sock, Opts, Trace) ->
   case pipe:recv(30000, []) of
      {http, _, {Code, Text, Head, _Env}} ->
         {Http, _} = htstream:encode({Code, Text, Head}, htstream:new()),
         printf(prot, Opts, "~s", [Http]),
         recv(Sock, Opts, Trace);

      {http, _, eof} ->
         recv(Sock, Opts, Trace);
   
      {http, _, Msg} when is_binary(Msg) ->
         printf(data, Opts, "~s", [Msg]),
         recv(Sock, Opts, Trace);

      {ioctl, _, _} ->
         recv(Sock, Opts, Trace);

      {trace, T, Msg} ->
         recv(Sock, Opts, [{T, Msg} | Trace]);

      '$free' ->
         trace(Opts, lists:reverse(Trace)),
         halt(0)
   end.

%%
%%
printf(prot, Opts, Fmt, Msg) ->
   case lists:member(verbose, Opts) of
      true ->
         io:format(Fmt, Msg);
      _    ->
         ok
   end;

printf(data, Opts, Fmt, Msg) ->
   case lists:member(silent, Opts) of
      true ->
         ok;
      _    ->
         io:format(Fmt, Msg)
   end;

printf(trace, Opts, Fmt, Msg) ->
   case lists:member(trace, Opts) of
      true ->
         io:format(Fmt, Msg);
      _    ->
         ok         
   end.   


trace(Opts, [T0 | Tail]) ->
   lists:foldl(
      fun({T, Msg}, T1) ->
         Ta = timer:now_diff(T, T0) / 1000,
         Td = timer:now_diff(T, T1) / 1000,
         case Msg of
            {tcp, connect, Y} ->
               X = timer:now_diff(Y, {0,0,0}) / 1000,
               printf(trace, Opts, "t (ms) ~9.3f : ~9.3f tcp ~9.3f ms~n", [Ta, Td, X]);
            {ssl, handshake, Y} ->
               X = timer:now_diff(Y, {0,0,0}) / 1000,
               printf(trace, Opts, "t (ms) ~9.3f : ~9.3f ssl ~9.3f ms~n", [Ta, Td, X]);
            {http, ttfb, Y} ->
               X = timer:now_diff(Y, {0,0,0}) / 1000,
               printf(trace, Opts, "t (ms) ~9.3f : ~9.3f http ttfb ~9.3f ms~n", [Ta, Td, X]);
            {http, ttmr, Y} ->
               X = timer:now_diff(Y, {0,0,0}) / 1000,
               printf(trace, Opts, "t (ms) ~9.3f : ~9.3f http ttmr ~9.3f ms~n", [Ta, Td, X]);
            {ssl, ca, Size} ->
               printf(trace, Opts, "t (ms) ~9.3f : ~9.3f ssl CA ~b byte~n", [Ta, Td, Size]);
            {ssl, peer, Size} ->
               printf(trace, Opts, "t (ms) ~9.3f : ~9.3f ssl Peer ~b byte~n", [Ta, Td, Size]);
            {_, packet, Size} ->
               printf(trace, Opts, "t (ms) ~9.3f : ~9.3f packet ~b byte~n", [Ta, Td, Size]);
            _ ->
               printf(trace, Opts, "t (ms) ~9.3f : ~9.3f ~p~n", [Ta, Td, Msg])
         end,
         T
      end,
      T0,
      Tail
   ).



