To compile, use: c(byzantine).
To run: byzantine:master(N,M,A) -> N = Total numbers of generals, M = Numbers of generals with traitors messengers, A = 1 ou 2.
A = 1 -> Algo oral messages
A = 2 -> Algo signed messages

/!\ We use the random module which is deprecated in the latest version of Erlang (now, we must use rand) so there is some warning during compilation.
/!\ If you want to use a version without warning, use the file byzantine_modern.erl
/!\ But to use it on the tEDA Env, use the file byzantine.erl