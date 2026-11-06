---
title: How to stop Claude from leaking personal data into your app
date: 20 Oct 2026
subtitle: Coding agents leak names and emails while trying to be helpful, and a few small habits catch it every time.
description: Why AI coding agents put names and emails where they should not go, and the instructions, checks and hooks that keep personal data on the right screens.
badges: [privacy, claude, ai agents, guardrails]
---

An AI coding agent writes code that works and passes its tests. A leak of personal data fits inside that description. The email address that shows up in the wrong place usually arrives as a small act of helpfulness.

A display name falls back to the email so the label is never blank. A profile picture gets a full description for screen readers, so it carries the person's name and email. A confirmation message repeats who submitted the form, and the confirmation goes to someone else. Each choice looks reasonable on its own line, and my own codebase had one of them in a helper.

A handful of habits keeps this out of your app, and they work with the agent as it is today. They are also the habits behind niji, the PII guardrails for Claude Code and Codex.

## Give the agent the rule in one sentence

Agents follow instructions that a machine could check. "Be careful with personal data" is too vague to apply. A sentence like this works better, and it is the one I use: a screen shows another person only what the page already prints in plain text for that viewer.

Put that sentence in the project instructions file the agent reads at the start of every session. Add the list of columns that identify a person, so the agent knows what the sentence covers. In my app that list is a single constant on the user model, and the instructions point at it.

## Give it a command that answers yes or no

A rule in prose gets forgotten halfway through a long task. A command gets run. Write a check that starts from your personal columns, follows them to every view, mail, helper and image, and exits with a failure when it finds an unreviewed read. Then tell the agent to run it before it calls a task done. This is the job niji does in my own project.

Telling the agent is a request, and a hook is a guarantee. Claude Code can run a script when the agent tries to finish, and a failing script sends the agent back to fix the problem. The [hooks reference](https://code.claude.com/docs/en/hooks) describes the events and the exit codes. A hook on the stop event that runs your check means a leak cannot be the last thing an agent leaves behind.

## Make silencing the check visible

Agents, like people, sometimes quiet a failing check instead of fixing the cause. Plan for it. Keep the reviewed exceptions in a file where every entry needs a reason in one sentence, and fail the run when an entry stops matching anything. A diff that adds an entry then shows a reason a human can read in seconds, and a diff that deletes the code but leaves the entry fails on its own.

Let entries pin what they cover as well. An entry marked as a name stops matching if the read later becomes an email. That catches the most common regression, a name that gains an email fallback.

## Pin the surfaces with tests

A check finds reads, and tests describe the result you want. Add a few assertions on the surfaces where leaks hide. The alt text of an avatar should be empty. A review should print a name or "Anonymous". The body of an email to one person should hold only that person's details.

These tests also give the agent a concrete failure to read. A message like "expected the page to exclude the reviewer's email address" is easier to act on than a general instruction.

## Read fallback chains in every diff

One pattern accounts for many leaks, a chain such as `name || email`. When you review an agent's change, look for any line that picks the first available value from several fields about a person. A good fallback for a missing name is a neutral word, such as "Anonymous" or "there".

## What it costs

The first run of a new check lists everything it cannot prove safe, and you read each hit. That took me a few hours on a mid-sized app, and about forty entries got a one-sentence reason. After that, each new hit is a small, specific question.

The check has limits. It follows direct reads and methods that return personal data. A value copied into a local variable and printed three steps later can slip past it, so the tests above stay useful.

## Your first move

Open the instructions file your agent reads and add the one-sentence rule. Then list your personal columns in one place, ask the agent to write the check, and watch it fail once on purpose by adding a name-or-email fallback to a review. A check you have seen fail is one you can rely on.
