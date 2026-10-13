//
//  CommandLineToolInstaller.swift
//  daisy
//

import Foundation

struct CommandLineTools {
    let launcher: URL
    let exporter: URL
    let resources: [URL]
}

nonisolated enum CommandLineToolInstaller {
    static func script(tools: CommandLineTools) -> String {
        """
        #!/bin/sh
        set -eu
        installer_path=$0
        trap 'rm -f "$installer_path"' EXIT
        bundled_cli=\(shellQuoted(tools.launcher.path))
        bundled_exporter=\(shellQuoted(tools.exporter.path))
        set -- \(tools.resources.map { shellQuoted($0.path) }.joined(separator: " "))

        path_contains() {
          case ":$PATH:" in
            *":$1:"*) return 0 ;;
            *) return 1 ;;
          esac
        }

        can_install_without_sudo() {
          dir="$1"
          if [ -d "$dir" ]; then
            [ -w "$dir" ] && [ -x "$dir" ]
            return
          fi

          parent="${dir%/*}"
          [ "$parent" != "$dir" ] || parent="."
          [ -d "$parent" ] && [ -w "$parent" ] && [ -x "$parent" ]
        }

        is_safe_path_dir() {
          case "$1" in
            ""|.|/bin|/sbin|/usr/bin|/usr/sbin|/System/*) return 1 ;;
            /*) return 0 ;;
            *) return 1 ;;
          esac
        }

        choose_install_dir() {
          for dir in "$HOME/.local/bin" "$HOME/bin"; do
            if path_contains "$dir" && can_install_without_sudo "$dir"; then
              printf '%s\t%s\n' "$dir" "false"
              return 0
            fi
          done

          old_ifs=$IFS
          IFS=:
          set -- $PATH
          IFS=$old_ifs

          for dir in /usr/local/bin /opt/homebrew/bin; do
            if path_contains "$dir"; then
              if can_install_without_sudo "$dir"; then
                printf '%s\t%s\n' "$dir" "false"
              else
                printf '%s\t%s\n' "$dir" "true"
              fi
              return 0
            fi
          done

          for dir do
            if is_safe_path_dir "$dir" && can_install_without_sudo "$dir"; then
              printf '%s\t%s\n' "$dir" "false"
              return 0
            fi
          done

          for dir do
            if is_safe_path_dir "$dir"; then
              printf '%s\t%s\n' "$dir" "true"
              return 0
            fi
          done

          return 1
        }

        choice=$(choose_install_dir) || {
          echo "Could not find a usable PATH directory for Daisy command line tools." >&2
          exit 1
        }

        install_dir=${choice%	*}
        needs_sudo=${choice#*	}
        primary="$install_dir/daisy"

        is_markdown_preview_launcher() {
          path="$1"
          [ -f "$path" ] && [ ! -L "$path" ] || return 1
          if grep -q '^# Managed by Markdown Preview CLI$' "$path"; then
            return 0
          fi
          grep -q 'exec open -b "doc.daisy"' "$path" ||
            grep -q 'exec open -b "doc.md-preview"' "$path"
        }

        can_replace_primary() {
          path="$1"
          if [ ! -e "$path" ] && [ ! -L "$path" ]; then
            return 0
          fi
          is_markdown_preview_launcher "$path"
        }

        can_replace_alias() {
          alias_path="$1"
          if [ ! -e "$alias_path" ] && [ ! -L "$alias_path" ]; then
            return 0
          fi
          [ -L "$alias_path" ] || return 1
          alias_target=$(readlink "$alias_path" || true)
          [ "$alias_target" = "daisy" ] ||
            [ "$alias_target" = "$primary" ] ||
            [ "$alias_target" = "$install_dir/daisy" ] ||
            [ "$alias_target" = "md-preview" ] ||
            [ "$alias_target" = "$install_dir/md-preview" ]
        }

        # Before the rename the primary command was md-preview, a launcher
        # script. Turn it into an alias so existing habits keep working, but
        # only if it is ours.
        can_replace_legacy_name() {
          path="$1"
          can_replace_alias "$path" || is_markdown_preview_launcher "$path"
        }

        refuse_existing_command() {
          echo "Refusing to replace existing command that was not installed by Daisy: $1" >&2
          exit 1
        }

        can_replace_primary "$primary" || refuse_existing_command "$primary"
        for alias in mdp markdown-preview; do
          can_replace_alias "$install_dir/$alias" || refuse_existing_command "$install_dir/$alias"
        done
        can_replace_legacy_name "$install_dir/md-preview" || refuse_existing_command "$install_dir/md-preview"

        run_install() {
          if [ "$needs_sudo" = "true" ]; then
            sudo "$@"
          else
            "$@"
          fi
        }

        exporter="$install_dir/.daisy-export"
        resources_dir="$install_dir/.daisy-resources"
        resources_tmp="$install_dir/.daisy-resources.tmp.$$"
        if [ "$needs_sudo" = "true" ]; then
          echo "Installing Daisy command line tools to $install_dir requires your password."
        fi
        run_install mkdir -p "$install_dir"
        run_install rm -rf "$resources_tmp"
        run_install mkdir "$resources_tmp"
        run_install install -m 755 "$bundled_cli" "$primary"
        run_install install -m 755 "$bundled_exporter" "$exporter"
        for resource do
          run_install install -m 644 "$resource" "$resources_tmp/$(basename "$resource")"
        done
        run_install rm -rf "$resources_dir"
        run_install mv "$resources_tmp" "$resources_dir"

        for alias in mdp markdown-preview md-preview; do
          alias_path="$install_dir/$alias"
          if [ "$needs_sudo" = "true" ]; then
            sudo ln -sfn "daisy" "$alias_path"
          else
            ln -sfn "daisy" "$alias_path"
          fi
        done

        echo
        echo "Daisy CLI is ready."
        echo
        echo "Use Daisy from any of these commands:"
        echo "  daisy"
        echo "  mdp                  Compatibility alias"
        echo "  markdown-preview     Compatibility alias"
        echo
        echo "Examples:"
        echo "  daisy README.md      Open a Markdown file"
        echo "  daisy .              Open the current folder"
        echo "  daisy export README.md --format docx --output README.docx"
        echo
        echo "Tips:"
        echo "  Re-run Install CLI... after updating the app to refresh these commands."
        echo "  Installed in: $install_dir"
        echo

        if command -v daisy >/dev/null 2>&1; then
          echo "Try it now: daisy ."
        else
          echo "Open a new terminal window, then try: daisy ."
        fi
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
