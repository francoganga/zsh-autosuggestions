
#--------------------------------------------------------------------#
# Async                                                              #
#--------------------------------------------------------------------#

_zsh_autosuggest_async_fetch_suggestion() {
	# Send the prefix to the pty to fetch a suggestion
	zpty -w -n $ZSH_AUTOSUGGEST_PTY_NAME "${1}"$'\0'
}

# Pty is spawned running this function
_zsh_autosuggest_async_suggestion_server() {
	emulate -R zsh

	# Output only newlines (not carriage return + newline)
	stty -onlcr

	local strategy=$1
	local last_pid

	while IFS='' read -r -d $'\0' prefix; do
		# Kill last bg process
		kill -KILL $last_pid &>/dev/null

		# Run suggestion search in the background
		(echo -n -E "$($strategy "$prefix")"$'\0') &

		last_pid=$!
	done
}

# Called when new data is ready to be read from the pty
# First arg will be fd ready for reading
# Second arg will be passed in case of error
_zsh_autosuggest_async_suggestion_ready() {
	local suggestion

	zpty -rt $ZSH_AUTOSUGGEST_PTY_NAME suggestion '*'$'\0' 2>/dev/null
	zle _autosuggest-show-suggestion "${suggestion%$'\0'}"
}

# Recreate the pty to get a fresh list of history events
_zsh_autosuggest_async_recreate_pty() {
	typeset -g _ZSH_AUTOSUGGEST_PTY_FD

	# Kill the old pty
	if [ -n "$_ZSH_AUTOSUGGEST_PTY_FD" ]; then
		# Remove the input handler
		zle -F $_ZSH_AUTOSUGGEST_PTY_FD

		# Destroy the pty
		zpty -d $ZSH_AUTOSUGGEST_PTY_NAME &>/dev/null
	fi

	# With newer versions of zsh, REPLY stores the fd to read from
	typeset -h REPLY

	# If we won't get a fd back from zpty, try to guess it
	if [ $_ZSH_AUTOSUGGEST_ZPTY_RETURNS_FD -eq 0 ]; then
		integer -l zptyfd
		exec {zptyfd}>&1  # Open a new file descriptor (above 10).
		exec {zptyfd}>&-  # Close it so it's free to be used by zpty.
	fi

	# Start a new pty running the server function
	zpty -b $ZSH_AUTOSUGGEST_PTY_NAME "_zsh_autosuggest_async_suggestion_server _zsh_autosuggest_strategy_$ZSH_AUTOSUGGEST_STRATEGY"

	# Store the fd so we can remove the handler later
	if (( REPLY )); then
		_ZSH_AUTOSUGGEST_PTY_FD=$REPLY
	else
		_ZSH_AUTOSUGGEST_PTY_FD=$zptyfd
	fi

	# Set up input handler from the pty
	zle -F $_ZSH_AUTOSUGGEST_PTY_FD _zsh_autosuggest_async_suggestion_ready
}
