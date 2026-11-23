#!/usr/bin/env bash
#
# delegate.sh: run coding agents as workers in tmux windows.
#
# A parent agent spawns workers, messages them, reads their screens and stops
# them. A worker reports back to the agent that spawned it. Run
# `delegate.sh help` for usage.
#
# Layout of this file:
#   1. Settings and usage
#   2. Shared helpers: tmux lookups, the worker tree, handoff files, typing into panes
#   3. Commands, one section each, in the order `help` lists them
#   4. Main: run the command
#
# Written for bash 3.2 (macOS) and later.

set -u

# =============================================================================
# 1. Settings and usage
# =============================================================================

SCRIPT=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
SKILL_MD=$(cd "$(dirname "$0")/.." && pwd)/SKILL.md

# Handoff files (long tasks, messages and reports) live under ROOT: one
# directory per parent pane, holding one directory per worker.
ROOT=${TMPDIR:-/tmp}
ROOT=${ROOT%/}/delegate
MARK=.delegate # marks a directory this script made, so it is safe to delete

INLINE_MAX=12000       # task bytes passed inline; tmux rejects a command over about 16 KB
LINE_MAX=1000          # characters typed as one message; longer ones go through a file
ENTER_DELAY=0.5        # seconds between typing a message and pressing Enter
FIRST_SCREEN_CHECKS=20 # spawn looks at a new worker's screen every 0.5 s, at most this many times

TAB=$(printf '\t')

usage() {
	cat <<'USAGE'
Usage: delegate.sh <command> [arguments]

Run coding agents as workers in tmux windows. A worker is addressed by the pane
id that `spawn` prints, such as %7. Every command must run inside tmux.

  check
      Say whether this shell can drive tmux.

  spawn [-n name] [-m model] [-c dir] [-e NAME=VALUE]... <agent> [-- agent-args...]
      Start a worker: <agent> is claude, codex or pi, run with its permission
      checks off. The task is read from stdin, for example:

          delegate.sh spawn -n review claude <<'EOF'
          Review src/auth for bugs ...
          EOF

      It becomes the worker's first prompt, followed by a footer telling the
      worker how to report to you. Prints the worker's pane id and name, then
      its first screen, which shows any startup prompt it is waiting on.
        -n  name for the window and the worker's reports (default: the agent)
        -m  model, passed to the agent's own model flag
        -c  working directory (default: the current one)
        -e  environment variable for the worker, repeatable. Workers get
            tmux's environment, not yours.

  send <pane> [message]
      Type a message into a worker and submit it. With no message, reads stdin.
      A long message is saved to a file and the worker is told to read it.

  key <pane> <key>...
      Press keys in a worker, named as for tmux send-keys: Escape interrupts
      its turn; Up, Down, Enter, digits and letters answer its prompts.

  read <pane> [lines]
      Print the last lines of a worker's screen (default 50).

  list
      Show the workers you spawned and the workers they spawned.

  stop [pane]
      Stop a worker and every worker it spawned, deleting their handoff files.
      With no pane, stop all of yours, plus any worker whose parent is gone.

  report [message]
      For workers: send a message to the agent that spawned you, prefixed with
      your name. With no message, reads stdin. A long message is saved to a
      file and its path is sent instead.

  help
      Print this help.
USAGE
}

# =============================================================================
# 2. Shared helpers
# =============================================================================

die() {
	printf 'delegate.sh: %s\n' "$*" >&2
	exit 1
}

# --- tmux lookups ------------------------------------------------------------

# get <pane> <format>: expand a tmux format for a pane; empty if the pane is gone.
get() { tmux display-message -p -t "$1" "$2" 2>/dev/null; }

# alive <pane>: whether the pane still exists.
alive() { [ "$(get "$1" '#{pane_id}')" = "$1" ]; }

# need_tmux: stop unless this shell can drive tmux. Sets SERVER to the tmux server's pid.
need_tmux() {
	[ -n "${TMUX_PANE:-}" ] || die "not inside tmux"
	command -v tmux >/dev/null 2>&1 || die "inside tmux, but there is no tmux on PATH"
	alive "$TMUX_PANE" || die "inside tmux, but the tmux server is unreachable; a sandbox may be blocking its socket"
	SERVER=$(get "$TMUX_PANE" '#{pid}')
}

# --- the worker tree ---------------------------------------------------------
#
# spawn tags each worker's window with three tmux options:
#   @parent         pane id of the agent that spawned it
#   @delegate_name  the worker's name, which prefixes its reports
#   @delegate_dir   the worker's handoff directory

# snapshot: save every pane as one tab-separated line in PANES, with the fields
#   1 pane id, 2 @parent, 3 window id, 4 @delegate_name, 5 @delegate_dir, 6 command, 7 dead (1 or 0)
snapshot() {
	PANES=$(tmux list-panes -a -F "#{pane_id}$TAB#{@parent}$TAB#{window_id}$TAB#{@delegate_name}$TAB#{@delegate_dir}$TAB#{pane_current_command}$TAB#{pane_dead}")
}

# children <pane>: the panes it spawned, from the snapshot.
children() { printf '%s\n' "$PANES" | awk -F "$TAB" -v p="$1" '$2 == p { print $1 }'; }

# field <pane> <n>: field n of the pane's line in the snapshot.
field() { printf '%s\n' "$PANES" | awk -F "$TAB" -v id="$1" -v n="$2" '$1 == id { print $n; exit }'; }

# mine <pane>: whether this pane spawned it, directly or through its workers.
mine() {
	local p=$1 i=0
	while [ $i -lt 100 ]; do
		p=$(get "$p" '#{@parent}')
		[ -n "$p" ] || return 1
		[ "$p" = "$TMUX_PANE" ] && return 0
		i=$((i + 1))
	done
	return 1
}

# need_worker <pane> <command>: stop unless the pane is one of this pane's workers.
need_worker() {
	[ -n "$1" ] || die "$2: name a worker's pane id, such as %7"
	alive "$1" || die "$2: no pane $1; the worker has exited"
	mine "$1" || die "$2: $1 is not one of your workers"
}

# --- handoff files -----------------------------------------------------------

# run_dir <pane>: the directory for the handoff files of the pane's workers.
run_dir() { printf '%s/%s-%s' "$ROOT" "$SERVER" "${1#%}"; }

# make_dir <dir>: create a directory and mark it as ours.
make_dir() { mkdir -p "$1" && : >"$1/$MARK"; }

# remove <dir>: delete a directory this script made, and nothing else.
remove() {
	case ${1:-} in */delegate/*) [ -f "$1/$MARK" ] && rm -rf "$1" ;; esac
	return 0
}

# --- typing into panes -------------------------------------------------------

# read_message [words...]: set MSG to the words, or to stdin when there are none.
read_message() {
	if [ $# -gt 0 ]; then
		MSG=$*
	elif [ ! -t 0 ]; then
		MSG=$(cat)
	else
		die "no message: pass it as an argument or on stdin"
	fi
	[ -n "$(printf '%s' "$MSG" | tr -d '[:space:]')" ] || die "the message is empty"
}

# wait_for_input <pane>: wait while someone has the pane in copy mode (scrolling
# back), since keys typed then go to copy mode instead of the agent.
wait_for_input() {
	local i=0
	while [ "$(get "$1" '#{pane_in_mode}')" = 1 ]; do
		[ $i -lt 120 ] || die "$1 has been in copy mode for a minute; try again once it leaves"
		sleep 0.5
		i=$((i + 1))
	done
}

# deliver <pane> <prefix> <kind> <dir>: type MSG into a pane as one line, then
# press Enter. A message too long to type is saved as <dir>/<kind>-N.md, and a
# line pointing to it is typed instead.
deliver() {
	local pane=$1 prefix=$2 kind=$3 dir=$4 line file n=1

	# Typed into a shell, the message would run as commands.
	case $(get "$pane" '#{pane_current_command}') in
	bash | zsh | sh | dash | fish | ksh | tcsh | csh | nu | -*)
		die "$pane is running a shell, not an agent; typing into it would run commands"
		;;
	esac

	line=$(printf '%s' "$MSG" | tr '\r\n\t' '   ')
	if [ ${#line} -gt $LINE_MAX ]; then
		[ -n "$dir" ] && [ -d "$dir" ] || die "the message is too long to type, and there is no handoff directory to save it in"
		while [ -e "$dir/$kind-$n.md" ]; do n=$((n + 1)); done
		file=$dir/$kind-$n.md
		printf '%s\n' "$MSG" >"$file" || die "can't write $file"
		case $kind in
		report) line="The full report is in $file." ;;
		*) line="My message was too long to type, so it is in $file. Read it and act on it as if I had typed it here." ;;
		esac
	fi

	wait_for_input "$pane"
	tmux send-keys -t "$pane" -l -- "$prefix$line" || die "couldn't type into $pane"
	# Enter goes separately, after a pause: sent with the text, it can land as a newline.
	sleep "$ENTER_DELAY"
	tmux send-keys -t "$pane" Enter
}

# =============================================================================
# 3. Commands
# =============================================================================

# -----------------------------------------------------------------------------
# check: say whether this shell can drive tmux
# -----------------------------------------------------------------------------

cmd_check() {
	if [ -z "${TMUX_PANE:-}" ]; then
		echo "not in tmux"
		return 1
	elif ! command -v tmux >/dev/null 2>&1; then
		echo "in tmux, but there is no tmux on PATH"
		return 2
	elif alive "$TMUX_PANE"; then
		echo "in tmux: $TMUX_PANE"
	else
		echo "in tmux, but the tmux server is unreachable; a sandbox may be blocking its socket"
		return 2
	fi
}

# -----------------------------------------------------------------------------
# spawn: start a worker
# -----------------------------------------------------------------------------

cmd_spawn() {
	need_tmux
	local name='' model='' dir=$PWD opt OPTIND=1 agent sid task prompt hand pane screen
	local -a envs
	envs=()

	# Options, the agent, then the agent's own arguments after --.
	while getopts ':n:m:c:e:' opt; do
		case $opt in
		n) name=$OPTARG ;;
		m) model=$OPTARG ;;
		c) dir=$OPTARG ;;
		e) envs+=(-e "$OPTARG") ;;
		:) die "spawn: -$OPTARG needs a value" ;;
		*) die "spawn: unknown option -$OPTARG; see: delegate.sh help" ;;
		esac
	done
	shift $((OPTIND - 1))
	agent=${1:-}
	[ -n "$agent" ] || die "spawn: name the agent: claude, codex or pi"
	shift
	if [ $# -gt 0 ]; then
		[ "$1" = -- ] || die "spawn: put the agent's own arguments after --"
		shift
	fi
	agent_command "$agent" "$model" "$@"
	[ -d "$dir" ] || die "spawn: no directory $dir"
	dir=$(cd "$dir" && pwd)
	sid=$(get "$TMUX_PANE" '#{session_id}')
	# An -e PATH=... replaces tmux's PATH, so tmux's only matters without one.
	case " ${envs[*]-} " in *" PATH="*) ;; *) check_tmux_path "$sid" "$agent" ;; esac

	# The worker's name, unique among this pane's workers.
	name=${name:-$agent}
	case $name in *[!A-Za-z0-9._-]*) die "spawn: a name may use only letters, digits, '.', '_' and '-'" ;; esac
	name=$(unique_name "$name")

	# The task, from stdin.
	[ ! -t 0 ] || die "spawn: give the task on stdin, for example with a <<'EOF' heredoc"
	task=$(cat)
	[ -n "$(printf '%s' "$task" | tr -d '[:space:]')" ] || die "spawn: the task on stdin is empty"

	# The worker's handoff directory, and its prompt: the task, then the footer.
	# A task too long to pass inline goes in the handoff directory instead.
	make_dir "$(run_dir "$TMUX_PANE")" || die "spawn: can't create $(run_dir "$TMUX_PANE")"
	hand=$(mktemp -d "$(run_dir "$TMUX_PANE")/$name.XXXXXX") || die "spawn: can't create a handoff directory"
	: >"$hand/$MARK"
	prompt="$task

$(worker_footer "$name" "$hand")"
	if [ "$(printf '%s' "$prompt" | wc -c | tr -d ' ')" -gt $INLINE_MAX ]; then
		printf '%s\n' "$task" >"$hand/task.md" || die "spawn: can't write $hand/task.md"
		prompt="Your task is in $hand/task.md. Read it, then do it.

$(worker_footer "$name" "$hand")"
	fi

	# The window, tagged as this pane's worker. A failed agent's pane is kept,
	# so that its error stays readable.
	pane=$(tmux new-window -d -P -F '#{pane_id}' -t "$sid:" -n "$name" -c "$dir" ${envs[@]+"${envs[@]}"} -- "${CMD[@]}" -- "$prompt") || {
		remove "$hand"
		die "spawn: tmux couldn't open a window"
	}
	tmux set-option -w -t "$pane" remain-on-exit failed 2>/dev/null
	if ! tmux set-option -w -t "$pane" @parent "$TMUX_PANE" \; set-option -w -t "$pane" @delegate_name "$name" \; set-option -w -t "$pane" @delegate_dir "$hand" 2>/dev/null; then
		remove "$hand"
		die "spawn: $agent exited as soon as it started; check its arguments"
	fi

	screen=$(first_screen "$pane" "$agent" "$hand") || exit 1
	printf '%s %s\n' "$pane" "$name"
	printf -- '--- first screen of %s ---\n' "$name"
	printf '%s\n' "$screen" | awk NF | tail -n 40
}

# agent_command <agent> <model> [agent-args...]: set CMD to the agent's command
# line, with its permission checks off.
agent_command() {
	local agent=$1 model=$2 model_flag
	shift 2
	case $agent in
	claude)
		CMD=(claude --dangerously-skip-permissions)
		model_flag=--model
		;;
	codex)
		CMD=(codex --dangerously-bypass-approvals-and-sandbox)
		model_flag=-m
		;;
	pi)
		# pi has no permission prompts; --approve answers its project-trust prompt.
		CMD=(pi --approve)
		model_flag=--model
		;;
	*) die "spawn: unknown agent '$agent'; use claude, codex or pi" ;;
	esac
	[ -z "$model" ] || CMD+=("$model_flag" "$model")
	CMD+=("$@")
}

# check_tmux_path <session> <agent>: stop unless the agent is on the PATH its
# window will get, which is tmux's and can differ from this shell's.
check_tmux_path() {
	local tpath
	tpath=$(tmux show-environment -t "$1" PATH 2>/dev/null) || tpath=
	case $tpath in PATH=*) ;; *) tpath=$(tmux show-environment -g PATH 2>/dev/null) ;; esac
	tpath=${tpath#PATH=}
	[ -n "$tpath" ] || return 0
	(PATH=$tpath && command -v "${CMD[0]}" >/dev/null 2>&1) ||
		die "spawn: $2 is not on tmux's PATH ($tpath); give the worker one that has it with -e PATH=..."
}

# unique_name <name>: the name, or the name with -2, -3 ... appended if another
# of this pane's workers already has it.
unique_name() {
	local name=$1 n=2
	snapshot
	while printf '%s\n' "$PANES" | awk -F "$TAB" -v p="$TMUX_PANE" -v nm="$name" '$2 == p && $4 == nm { f = 1 } END { exit !f }'; do
		name=$1-$n
		n=$((n + 1))
	done
	printf '%s\n' "$name"
}

# worker_footer <name> <handoff dir>: the text spawn appends to a worker's task.
worker_footer() {
	cat <<FOOTER
---
You are worker "$1", started by another agent. Treat that agent as your user for this task: it doesn't see your replies here, only what you send with
    $(printf '%q' "$SCRIPT") report "<message>"
Long text can be piped in instead (report <<'EOF'); it is saved to a file and the agent is sent its path.
- When you finish, report your result.
- To ask the agent something, report the question. The answer arrives as your next message.
- Put any file you hand back in $2. It is deleted when you are stopped.
- To give part of this task to another agent, follow $SKILL_MD.
FOOTER
}

# first_screen <pane> <agent> <handoff dir>: wait until a new worker's screen
# stops changing, then print it. If the agent exits during startup, remove its
# window and handoff directory, and stop with its error.
first_screen() {
	local pane=$1 agent=$2 hand=$3 screen='' prev='' still=0 i=0
	while [ $i -lt $FIRST_SCREEN_CHECKS ]; do
		sleep 0.5
		i=$((i + 1))
		if [ "$(get "$pane" '#{pane_dead}')" = 1 ]; then
			screen=$(tmux capture-pane -p -J -t "$pane" -S - | awk NF | tail -n 20)
			tmux kill-window -t "$(get "$pane" '#{window_id}')"
			remove "$hand"
			die "spawn: $agent exited during startup:
$screen"
		fi
		if ! alive "$pane"; then
			remove "$hand"
			die "spawn: $agent exited during startup; check its arguments"
		fi
		screen=$(tmux capture-pane -p -J -t "$pane")
		if [ -n "$(printf '%s' "$screen" | tr -d '[:space:]')" ] && [ "$screen" = "$prev" ]; then
			still=$((still + 1))
			[ $still -ge 2 ] && break
		else
			still=0
		fi
		prev=$screen
	done
	printf '%s\n' "$screen"
}

# -----------------------------------------------------------------------------
# send: type a message into a worker and submit it
# -----------------------------------------------------------------------------

cmd_send() {
	need_tmux
	local pane=${1:-}
	need_worker "$pane" send
	shift
	read_message "$@"
	deliver "$pane" '' message "$(get "$pane" '#{@delegate_dir}')"
	echo "sent to $pane"
}

# -----------------------------------------------------------------------------
# key: press keys in a worker
# -----------------------------------------------------------------------------

cmd_key() {
	need_tmux
	local pane=${1:-}
	need_worker "$pane" key
	shift
	[ $# -gt 0 ] || die "key: name at least one key, such as Escape"
	wait_for_input "$pane"
	tmux send-keys -t "$pane" "$@"
}

# -----------------------------------------------------------------------------
# read: print the last lines of a worker's screen
# -----------------------------------------------------------------------------

cmd_read() {
	need_tmux
	local pane=${1:-} lines=${2:-50}
	need_worker "$pane" read
	case $lines in '' | *[!0-9]*) die "read: lines must be a number" ;; esac
	tmux capture-pane -p -J -t "$pane" -S - | awk NF | tail -n "$lines"
}

# -----------------------------------------------------------------------------
# list: show the workers you spawned and the workers they spawned
# -----------------------------------------------------------------------------

cmd_list() {
	need_tmux
	snapshot
	local tree
	tree=$(print_tree "$TMUX_PANE" '')
	if [ -n "$tree" ]; then printf '%s\n' "$tree"; else echo "no workers"; fi
}

# print_tree <pane> <indent>: print the pane's workers and theirs, depth first.
print_tree() {
	local c state
	for c in $(children "$1"); do
		state=$(field "$c" 6)
		[ "$(field "$c" 7)" = 1 ] && state=exited
		printf '%s%s  %s  (%s)\n' "$2" "$c" "$(field "$c" 4)" "$state"
		print_tree "$c" "$2    "
	done
}

# -----------------------------------------------------------------------------
# stop: stop workers and delete their handoff files
# -----------------------------------------------------------------------------

cmd_stop() {
	need_tmux
	snapshot
	if [ $# -gt 0 ]; then
		if ! alive "$1"; then
			echo "$1 has already exited"
			return 0
		fi
		need_worker "$1" stop
		stop_tree "$1"
	else
		stop_tree "$TMUX_PANE"
		sweep
		remove "$(run_dir "$TMUX_PANE")"
	fi
}

# stop_tree <pane>: stop the pane's workers, depth first, then the pane itself
# unless it is this one, deleting each stopped worker's handoff files.
stop_tree() {
	local c
	for c in $(children "$1"); do stop_tree "$c"; done
	[ "$1" = "$TMUX_PANE" ] && return 0
	tmux kill-window -t "$(field "$1" 3)" 2>/dev/null
	remove "$(field "$1" 5)"
	remove "$(run_dir "$1")"
	printf 'stopped %s %s\n' "$1" "$(field "$1" 4)"
}

# sweep: stop workers whose parent pane is gone, and delete the handoff
# directories no live pane owns: those of gone panes on this tmux server, and
# those of tmux servers that have stopped.
sweep() {
	local live p d base server pane
	live=" $(printf '%s\n' "$PANES" | cut -f1 | tr '\n' ' ') "

	for p in $(printf '%s\n' "$PANES" | awk -F "$TAB" '$2 != "" { print $1 }'); do
		case $live in *" $(field "$p" 2) "*) ;; *) stop_tree "$p" ;; esac
	done

	for d in "$ROOT"/*-*; do
		[ -d "$d" ] || continue
		base=${d##*/} # <server pid>-<pane number>
		server=${base%%-*}
		pane=%${base#*-}
		if [ "$server" = "$SERVER" ]; then
			case $live in *" $pane "*) continue ;; esac
		elif kill -0 "$server" 2>/dev/null; then
			continue # another tmux server, still running, owns it
		fi
		remove "$d"
	done
}

# -----------------------------------------------------------------------------
# report: (workers) send a message to the agent that spawned you
# -----------------------------------------------------------------------------

cmd_report() {
	need_tmux
	local parent name
	parent=$(get "$TMUX_PANE" '#{@parent}')
	[ -n "$parent" ] || die "report: this pane wasn't started by 'delegate.sh spawn', so there is no one to report to"
	alive "$parent" || die "report: the agent that started you ($parent) is gone"
	name=$(get "$TMUX_PANE" '#{@delegate_name}')
	read_message "$@"
	deliver "$parent" "[$name] " report "$(get "$TMUX_PANE" '#{@delegate_dir}')"
	echo "reported to the agent that started you ($parent)"
}

# =============================================================================
# 4. Main
# =============================================================================

main() {
	local command_name=${1:-help}
	[ $# -gt 0 ] && shift
	case $command_name in
	check) cmd_check ;;
	spawn) cmd_spawn "$@" ;;
	send) cmd_send "$@" ;;
	key) cmd_key "$@" ;;
	read) cmd_read "$@" ;;
	list) cmd_list ;;
	stop) cmd_stop "$@" ;;
	report) cmd_report "$@" ;;
	help | -h | --help) usage ;;
	*)
		usage >&2
		return 1
		;;
	esac
}

main "$@"
