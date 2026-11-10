#!/usr/bin/env escript
%%! +S 2:2 +A 1
-mode(compile).
main([Producer, SpecFile, Output]) ->
    try
        {ok, SpecBytes} = file:read_file(SpecFile),
        Spec = json:decode(SpecBytes),
        Runtime = unicode:characters_to_binary(code:root_dir()),
        {ok, RuntimeBytes} = file:read_file(filename:join(Producer, "otp-runtime.json")),
        NativeRuntime = maps:get(<<"runtimeRoot">>, json:decode(RuntimeBytes)),
        case Runtime =:= NativeRuntime andalso Runtime =:= maps:get(<<"runtimeRoot">>, Spec) of
            true -> ok;
            false -> error(sdk_runtime_mismatch)
        end,
        put(sdk_roots, [code:root_dir()]),
        Directory = filename:join([Producer, "build", "erlang-shipment"]),
        Rows = [application(Directory, binary_to_atom(maps:get(<<"name">>, A)), binary_to_list(maps:get(<<"version">>, A)), binary_to_list(maps:get(<<"package">>, A))) || A <- maps:get(<<"applications">>, Spec), filelib:is_dir(filename:join(Directory, binary_to_list(maps:get(<<"package">>, A))))],
        Names = [maps:get(name, A) || A <- Rows],
        true = length(Names) =:= length(lists:usort(Names)),
        true = lists:all(fun(R) -> lists:member(R, Names) end, maps:get(<<"roots">>, Spec)),
        lists:foreach(fun(A) ->
            Required = maps:get(required, A) -- maps:get(optional, A),
            true = lists:all(fun(D) -> lists:member(D, Names) orelse sdk_application(D) end, Required ++ maps:get(included, A))
        end, Rows),
        true = lists:all(fun(A) -> not maps:get(sdk, A) end, Rows),
        Modules = lists:append([maps:get(modules, A) || A <- Rows]),
        ModuleNames = [maps:get(name, M) || M <- Modules],
        case length(ModuleNames) =:= length(lists:usort(ModuleNames)) of
            true -> ok;
            false -> error(duplicate_compiled_module_owners)
        end,
        {ok, Compiler} = file:read_file(filename:join(Producer, "otp-compiler-version.txt")),
        Model = #{kind => <<"compiled-native-gleam-application-set">>, selection => Spec,
            nativeShipment => unicode:characters_to_binary(Directory),
            producer => unicode:characters_to_binary(Producer),
            otp => unicode:characters_to_binary(erlang:system_info(otp_release)),
            erts => unicode:characters_to_binary(erlang:system_info(version)),
            architecture => unicode:characters_to_binary(erlang:system_info(system_architecture)),
            compilerVersion => string:trim(Compiler), runtimeRoot => Runtime, applications => Rows},
        ok = file:write_file(Output, json:encode(Model))
    catch Class:Reason:Stack ->
        io:format(standard_error, "Native OTP stack: ~0p~ngleam-purifier: compiled OTP selection: ~0p:~0p~n", [Stack,Class,Reason]), halt(1)
    end.
sdk_application(Name) ->
    case code:lib_dir(binary_to_atom(Name)) of
        {error, bad_name} -> false;
        Path -> is_sdk_path(Path)
    end.

application(Root, App, Version, Package) ->
    Dir = filename:join([Root, Package]),
    AppFile = filename:join([Dir, "ebin", atom_to_list(App) ++ ".app"]),
    {ok, [{application, App, Props}]} = file:consult(AppFile),
    Version = proplists:get_value(vsn, Props),
    SdkDir =
        case code:lib_dir(App) of
            {error, bad_name} ->
                false;
            Path ->
                case is_sdk_path(Path) of
                    true -> Path;
                    false -> false
                end
        end,
    Beams = filelib:wildcard(filename:join([Dir, "ebin", "*.beam"])),
    Modules = [module(B, SdkDir) || B <- lists:sort(Beams)],
    Actual = [binary_to_atom(maps:get(name, M)) || M <- Modules],
    true = lists:all(
        fun(M) -> lists:member(M, Actual) end, proplists:get_value(modules, Props, [])
    ),
    Files = lists:sort(filelib:fold_files(Dir, ".*", true, fun(F, Acc) -> [F | Acc] end, [])),
    Evidence = [file(F, Dir, SdkDir) || F <- Files],
    #{
        name => atom_to_binary(App),
        version => unicode:characters_to_binary(Version),
        directory => unicode:characters_to_binary(Dir),
        sdk => SdkDir =/= false,
        required => [atom_to_binary(A) || A <- proplists:get_value(applications, Props, [])],
        included => [
            atom_to_binary(A)
         || A <- proplists:get_value(included_applications, Props, [])
        ],
        optional => [
            atom_to_binary(A)
         || A <- proplists:get_value(optional_applications, Props, [])
        ],
        modules => Modules,
        files => Evidence
    }.

module(File, Sdk) ->
    {ok, Mod, Chunks} = beam_lib:all_chunks(File),
    true = atom_to_list(Mod) =:= filename:basename(File, ".beam"),
    {ok, {Mod, MD5}} = beam_lib:md5(File),
    Base = #{
        name => atom_to_binary(Mod), sha256 => hash_file(File), codeMD5 => binary:encode_hex(MD5)
    },
    case Sdk of
        false ->
            case code:which(Mod) of
                preloaded ->
                    error({sdk_module_collision, Mod});
                P when is_list(P) ->
                    case is_sdk_path(P) of
                        true -> error({sdk_module_collision, Mod});
                        false -> Base
                    end;
                _ ->
                    Base
            end;
        _ ->
            Original = filename:join([Sdk, "ebin", filename:basename(File)]),
            {ok, Mod, SdkChunks} = beam_lib:all_chunks(Original),
            %% Native Mix release stripping removes compiler/debug/local-function
            %% information, including Elixir checker metadata (ExCk).
            %% Every remaining chunk and native code MD5 agrees.
            Strip = ["LocT", "CInf", "Dbgi", "Docs", "Abst", "ExCk"],
            Semantic = fun(C) ->
                lists:sort([{K, V} || {K, V} <- C, not lists:member(K, Strip)])
            end,
            case Semantic(Chunks) =:= Semantic(SdkChunks) of
                true -> ok;
                false -> error({altered_sdk_beam, Mod})
            end,
            {ok, {Mod, MD5}} = beam_lib:md5(Original),
            Base#{
                sdkFile => unicode:characters_to_binary(Original),
                sdkSHA256 => hash_file(Original),
                comparison => <<"native-code-MD5-and-all-nondebug-chunks">>
            }
    end.

file(File, Root, Sdk) ->
    Relative = string:prefix(File, Root ++ "/"),
    true = is_list(Relative),
    {ok, Bytes} = file:read_file(File),
    case Sdk of
        false ->
            Extension = filename:extension(File),
            NativeMagic =
                case Bytes of
                    <<127, "ELF", _/binary>> -> true;
                    <<"MZ", _/binary>> -> true;
                    _ -> false
                end,
            case
                NativeMagic orelse
                    lists:member(Extension, [".so", ".dylib", ".dll", ".nif", ".a", ".o"])
            of
                true -> error({native_application_payload_needs_runtime_proof, Relative});
                false -> ok
            end;
        _ ->
            case filename:extension(File) of
                ".beam" -> ok;
                ".app" ->
                    %% Mix serializes native application terms without comments.
                    %% Compare parsed terms rather than claiming byte equality.
                    {ok, Terms} = file:consult(File),
                    {ok, Terms} = file:consult(filename:join(Sdk, Relative));
                _ -> {ok, Bytes} = file:read_file(filename:join(Sdk, Relative))
            end
    end,
    Evidence = #{path => unicode:characters_to_binary(Relative), sha256 => hash(Bytes)},
    case Sdk of
        false -> Evidence;
        _ ->
            Original = filename:join(Sdk, Relative),
            Comparison = case filename:extension(File) of
                ".beam" -> <<"native-code-MD5-and-all-runtime-chunks">>;
                ".app" -> <<"native-consult-term-equality">>;
                _ -> <<"byte-equality">>
            end,
            Evidence#{sdkFile => unicode:characters_to_binary(Original), sdkSHA256 => hash_file(Original), comparison => Comparison}
    end.
hash_file(File) ->
    {ok, Bytes} = file:read_file(File),
    hash(Bytes).
hash(Bytes) -> string:lowercase(binary:encode_hex(crypto:hash(sha256, Bytes))).

is_sdk_path(Path) ->
    lists:any(fun(Root) -> lists:prefix(Root ++ "/", Path) end, get(sdk_roots)).
