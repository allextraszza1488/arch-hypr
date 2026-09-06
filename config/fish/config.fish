if status is-interactive
    # Modern CLI replacements, falling back cleanly if not installed yet
    # (sudo bash ~/arch-setup/install-cli-tools.sh installs all of these).
    if type -q eza
        alias ls='eza --group-directories-first --icons'
        alias ll='eza -l --group-directories-first --icons'
        alias la='eza -la --group-directories-first --icons'
        alias dir='eza -la --group-directories-first --icons'  # Windows/DOS muscle memory
        alias tree='eza --tree --icons'
    else
        alias ll='ls -lh --color=auto'
        alias la='ls -lah --color=auto'
        alias dir='ls -lah --color=auto'
    end
    # `type -q X and Y` looked right but isn't: fish only treats `and` as a
    # job-separator when it starts a new statement (after `;` or a newline),
    # not just because it's the next word on the line. Written inline like
    # that, the whole line becomes ONE call to `type` with everything after
    # it -- including `--cmd`/`--fish` -- passed as literal arguments, which
    # `type` then rejects as unknown flags. Confirmed by reproducing it
    # directly in `fish -c` before writing this fix. `if`/`end` has no such
    # ambiguity.
    if type -q bat
        alias cat='bat --paging=never'
    end
    if type -q zoxide
        zoxide init fish --cmd cd | source
    end
    if type -q fzf
        fzf --fish | source
    end

    # Commands to run in interactive sessions can go here
    command cat ~/.config/fish/art.ascii.txt  # bypass the cat->bat alias above: plain art, no syntax box
    echo ""
    echo "  kitty  ctrl+shift+enter new win  ·  ctrl+shift+t new tab  ·  ctrl+shift+w close window · ctrl+shift+q close tab"
    echo "         ctrl+shift+←/→ switch tab ·  ctrl+shift+c/v copy/paste ·  ctrl+shift+f search"
    echo "         ctrl+shift+=/- font size  ·  ctrl+shift+f5 reload config"
    echo ""
end
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
fish_add_path $HOME/.local/bin

# >>> grok installer >>>
fish_add_path $HOME/.grok/bin
# <<< grok installer <<<
