#!/usr/bin/env zsh

_fzf_complete_awk_functions='
    function colorize_git_status(input, color1, color2, reset) {
        index_status = substr(input, 1, 1)
        work_tree_status = substr(input, 2, 1)

        if (index_status ~ /[MADRC]/) {
            index_status_color = color1
        }
        if (index_status work_tree_status ~ /(D[DU]|A[AU])|U.|\?\?|!!/) {
            index_status_color = color2
        }
        if (work_tree_status ~ /[MADRCU\?!]/) {
            work_tree_status_color = color2
        }

        return sprintf("%s%s%s%s%s%s %s", index_status_color, index_status, reset, work_tree_status_color, work_tree_status, reset, substr(input, 4))
    }

    function trim_prefix(str, prefix) {
        match(str, prefix)
        return substr(str, RSTART + RLENGTH)
    }
'

_fzf_complete_preview_git_diff=$(cat <<'PREVIEW_OPTIONS'
    --preview-window=right:70%:wrap
    --preview='echo {} | awk -v RS="" '\''
        {
            status = substr($0, 1, 2)
            input = substr($0, 4)

            if (status ~ /^(\?\?|!!)/) {
                printf "%s%c%s", "/dev/null", 0, input
            } else {
                printf "%s", input
            }
        }
    '\'' | xargs -0 git diff --no-ext-diff --color=always --'
PREVIEW_OPTIONS
)

_fzf_complete_git() {
    local arguments=$@
    local resolved_commands=()
    local arguments_num=${#${(z)arguments}}

    while true; do
        local resolved=$(_fzf_complete_git_resolve_alias ${(Qz)arguments})
        if [[ -z $resolved ]]; then
            break
        fi

        local subcommand=${${(Qz)resolved}[2]}
        if [[ ${resolved_commands[(r)$subcommand]} = $subcommand ]]; then
            break
        fi

        arguments=$resolved
        resolved_commands+=($subcommand)
    done

    local last_argument=${${(Qz)arguments}[-1]}

    if [[ ${(Q)arguments} =~ '^git (checkout|log|rebase|reset)' ]]; then
        _fzf_complete_git-commits '' $@
        return
    fi

    if [[ ${(Q)arguments} =~ '^git (branch|cherry-pick|merge)' ]]; then
        _fzf_complete_git-commits '--multi' $@
        return
    fi

    if [[ ${(Q)arguments} = 'git commit'* ]]; then
        if [[ $prefix =~ '^--(fixup|reedit-message|reuse-message|squash)=' ]]; then
            prefix_option=${prefix/=*/=} _fzf_complete_git-commits '' $@
            return
        fi

        if [[ $last_argument =~ '^(-[^-]*[cC]|--(reuse-message|reedit-message|fixup|squash))$' ]]; then
            _fzf_complete_git-commits '' $@
            return
        fi

        if [[ $prefix =~ '^--message=' ]]; then
            prefix_option=${prefix/=*/=} _fzf_complete_git-commit-messages '' $@
            return
        fi

        if [[ $last_argument =~ '^(-[^-]*m|--message)$' ]]; then
            _fzf_complete_git-commit-messages '' $@
            return
        fi

        if [[ $prefix =~ '^--author=' ]]; then
            return
        fi

        if [[ $last_argument = '--author' ]]; then
            return
        fi

        if [[ $prefix =~ '^--date=' ]]; then
            return
        fi

        if [[ $last_argument = '--date' ]]; then
            return
        fi

        if [[ $prefix =~ '^--(file|template|pathspec-from-file)=$' ]]; then
            _fzf_path_completion '' $@$prefix
            return
        fi

        if [[ $last_argument =~ '^(-[^-]*[Ft]|--(file|template|pathspec-from-file))$' ]]; then
            _fzf_path_completion '' $@
            return
        fi

        local cleanup_mode=(strip whitespace verbatim scissors default)
        if [[ $prefix =~ '^--cleanup=' ]]; then
            _fzf_complete '' $@ < <(awk -v prefix=${prefix/=*/=} '{ print prefix $0 }' <<< ${(F)cleanup_mode})
            return
        fi

        if [[ $last_argument = '--cleanup' ]]; then
            _fzf_complete '' $@ <<< ${(F)cleanup_mode}
            return
        fi

        local untracked_file_mode=(no normal all)
        if [[ $prefix =~ '^--untracked-files=' ]]; then
            _fzf_complete '' $@ < <(awk -v prefix=${prefix/=*/=} '{ print prefix $0 }' <<< ${(F)untracked_file_mode})
            return
        fi

        if [[ $last_argument =~ '^(-[^-]*u|--untracked-files)$' ]]; then
            _fzf_complete '' $@ <<< ${(F)untracked_file_mode}
            return
        fi

        _fzf_complete_git-unstaged-files '--multi' $@
        return
    fi

    if [[ ${(Q)arguments} = 'git add'* ]]; then
        _fzf_complete_git-unstaged-files "--multi $_fzf_complete_preview_git_diff $FZF_DEFAULT_OPTS" $@
        return
    fi

    if [[ ${(Q)arguments} = 'git pull'* ]]; then
        # TODO: Use the number of removing options instead of $arguments_num
        if [[ $arguments_num = 2 ]]; then
            _fzf_complete_git-remotes '' $@
            return
        fi

        if [[ $arguments_num = 3 ]]; then
            # TODO: Stop hard coding for $repository
            repository=${${(Qz)arguments}[3]} _fzf_complete_git-refs '' $@
            return
        fi
    fi

    _fzf_path_completion $prefix $@
}

_fzf_complete_git-commits() {
    local fzf_options=$1
    shift

    _fzf_complete "--ansi --tiebreak=index $fzf_options" $@ < <({
        git for-each-ref refs/heads refs/remotes refs/tags --format='%(refname:short) %(contents:subject)' 2> /dev/null
        git log --format='%h %s' 2> /dev/null
    } | awk -v prefix=$prefix_option '{ print prefix $0 }' | _fzf_complete_git_tabularize)
}

_fzf_complete_git-commits_post() {
    awk '{ print $1 }'
}

_fzf_complete_git-commit-messages() {
    local fzf_options=$1
    shift

    _fzf_complete "--ansi --tiebreak=index $fzf_options" $@ < <(
        git log --format='%h %s' 2> /dev/null |
        awk -v prefix=$prefix_option '
            {
                match($0, / /)
                print $1, prefix substr($0, RSTART + RLENGTH)
            }
        ' | _fzf_complete_git_tabularize
    )
}

_fzf_complete_git-commit-messages_post() {
    local message=$(awk -v prefix=$prefix_option '
        '$_fzf_complete_awk_functions'
        {
            match($0, /  /)
            str = substr($0, RSTART + RLENGTH)
            print trim_prefix(str, prefix)
        }
    ')
    if [[ -z $message ]]; then
        return
    fi

    echo $prefix_option${(qq)message}
}

_fzf_complete_git-unstaged-files() {
    local fzf_options=$1
    shift

    _fzf_complete "--ansi --read0 --print0 $fzf_options" $@ < <({
        local previous_status
        local filename
        local files=$(git status --untracked-files=all --porcelain=v1 -z 2> /dev/null)

        for filename in ${(0)files}; do
            if [[ $previous_status != R ]]; then
                awk \
                    -v RS='' \
                    -v green=$(tput setaf 2) \
                    -v red=$(tput setaf 1) \
                    -v reset=$(tput sgr0) '
                            '$_fzf_complete_awk_functions'
                            /^.[^ ]/ {
                            printf "%s%c", colorize_git_status($0, green, red, reset), 0
                        }
                    ' <<< $filename
            fi

            previous_status=${filename:0:1}
        done
    })
}

_fzf_complete_git-unstaged-files_post() {
    local filename
    local input=$(cat)

    for filename in ${(0)input}; do
        echo ${${(q+)filename:3}//\\n/\\\\n}
    done
}

_fzf_complete_git-remotes() {
    local fzf_options="$1"
    shift

    _fzf_complete "--ansi $fzf_options" $@ < <(git remote --verbose | awk '
        /\(fetch\)$/ {
            gsub("\t", " ")
            print
        }
    ' | _fzf_complete_git_tabularize)
}

_fzf_complete_git-remotes_post() {
    awk '{ print $1 }'
}

_fzf_complete_git-refs() {
    local fzf_options=$1
    shift

    local ref=${${$(git config remote.origin.fetch 2> /dev/null)#*:}%\*}

    _fzf_complete "--ansi --tiebreak=index $fzf_options" $@ < <(
        git for-each-ref $ref --format='%(refname:short) %(contents:subject)' 2> /dev/null |
        awk -v prefix=$prefix_option '{ print prefix $0 }' | _fzf_complete_git_tabularize
    )
}

_fzf_complete_git-refs_post() {
    input=$(cat)

    if [[ -z $input ]]; then
        return
    fi

    echo ${${input#*/}%% *}
}

_fzf_complete_git_resolve_alias() {
    local git_alias git_alias_resolved
    local git_aliases=$(git config --get-regexp '^alias\.')

    for git_alias in ${(f)git_aliases}; do
        if [[ ${${git_alias#alias.}%% *} = $2 ]]; then
            git_alias_resolved="$1 ${git_alias#* } ${@:3}"
        fi
    done

    echo $git_alias_resolved
}

_fzf_complete_git_tabularize() {
    awk \
        -v yellow=$(tput setaf 3) \
        -v reset=$(tput sgr0) '
        {
            refnames[NR] = $1

            if (length($1) > refname_max) {
                refname_max = length($1)
            }

            match($0, / /)
            messages[NR] = substr($0, RSTART + RLENGTH)
        }
        END {
            for (i = 1; i <= length(refnames); ++i) {
                printf "%s%-" refname_max "s %s %s\n", yellow, refnames[i], reset, messages[i]
            }
        }
    '
}
