#!/usr/bin/env bash
# Déduit le mode du pipeline (release | preview | ci) de l'événement GitHub.
#
#   push sur la branche par défaut         -> release
#   push sur une autre branche             -> ci
#   pull_request avec le label `preview`   -> preview
#   pull_request sans ce label             -> ci
#   workflow_dispatch                      -> input `mode` du déclenchement (défaut : release)
#   autre événement (schedule…)            -> ci
#
# Variables d'entrée :
#   REQUESTED_MODE    auto | release | preview | ci  (forcé par l'appelant si différent de auto)
#   REQUESTED_BUMP    auto | patch | minor | major
#   EVENT_NAME, REF, DEFAULT_BRANCH
#   DISPATCH_MODE, DISPATCH_BUMP     inputs du workflow_dispatch, s'il y en a
#   PREVIEW_LABEL     true si la PR porte le label preview
#   PR_NUMBER         numéro de la PR, s'il y en a
#
# Sorties (dans $GITHUB_OUTPUT, sinon sur stdout) : mode, bump, pr-number
set -euo pipefail

die() { echo "::error::$*" >&2; exit 1; }

requested="${REQUESTED_MODE:-auto}"
default_ref="refs/heads/${DEFAULT_BRANCH:-main}"

if [ "$requested" != auto ]; then
  mode="$requested"
else
  case "${EVENT_NAME:-}" in
    push)
      if [ "${REF:-}" = "$default_ref" ]; then mode=release; else mode=ci; fi ;;
    pull_request | pull_request_target)
      if [ "${PREVIEW_LABEL:-false}" = true ]; then mode=preview; else mode=ci; fi ;;
    workflow_dispatch)
      mode="${DISPATCH_MODE:-release}" ;;
    *)
      mode=ci ;;
  esac
fi

case "$mode" in release | preview | ci) ;; *) die "mode invalide : $mode" ;; esac

if [ "$mode" = release ] && [ "${REF:-}" != "$default_ref" ]; then
  die "une release se fait depuis ${DEFAULT_BRANCH:-main} (ref actuelle : ${REF:-inconnue})"
fi

bump="${REQUESTED_BUMP:-auto}"
if [ "$bump" = auto ] && [ -n "${DISPATCH_BUMP:-}" ]; then
  bump="$DISPATCH_BUMP"
fi
case "$bump" in auto | patch | minor | major) ;; *) die "bump invalide : $bump" ;; esac

{
  echo "mode=$mode"
  echo "bump=$bump"
  echo "pr-number=${PR_NUMBER:-}"
} | tee -a "${GITHUB_OUTPUT:-/dev/null}"
