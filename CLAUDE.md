# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal notes repository containing markdown files on various topics including:
- SaaS business ideas (trade compliance, cosmetics regulations, duty drawback)
- Scrum and agile development practices
- Technical notes (TypeScript, Rust, multi-cursor editing)

## Structure

- Root directory contains topic notes (`.md` files); daily notes live under `notes/` (e.g., `notes/2025-12-07.md`)
- `.github/workflows/daily_note.yml` - GitHub Actions workflow that creates a daily note at midnight UTC
- `.github/workflows/weekly_review.yml` - weekly review workflow; `scripts/` contains an Obsidian sync watcher (launchd plist + shell scripts)

## Automation

The repository has a daily GitHub Actions workflow that automatically creates a new note file in a `notes/` directory with the current date.
