# Keep the user's prompt and config.fish. Reload colors before the next prompt.
status is-interactive; or return

function __victoria_wallust_refresh --on-event fish_prompt
    set -l cache "$HOME/.cache"
    if set -q XDG_CACHE_HOME; and test -n "$XDG_CACHE_HOME"
        set cache "$XDG_CACHE_HOME"
    end
    set -l directory "$cache/wallust"
    test -r "$directory/victoria-generation"; or return
    set -l generation
    read -l generation < "$directory/victoria-generation"
    if set -q __victoria_wallust_generation; and test "$generation" = "$__victoria_wallust_generation"
        return
    end
    if test -r "$directory/victoria-colors.fish"
        source "$directory/victoria-colors.fish"
    end
    if test -t 1; and test "$TERM" != dumb; and test "$TERM" != linux; and test -r "$directory/sequences"
        cat "$directory/sequences"
    end
    set -g __victoria_wallust_generation "$generation"
end

__victoria_wallust_refresh
