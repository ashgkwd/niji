---
title: Four guardrails for personal data in agent-written code
date: 20 Oct 2026
subtitle: How to detect leaked names and emails deterministically, by tracing from the model to the screen and judging each read by who is looking.
description: A design for detecting personal data leaks in code that AI agents write, by declaring the source, tracing to every screen, judging the viewer and testing failures.
badges: [privacy, guardrails, static analysis, ai agents]
---

Agents write more and more of the views, helpers and mailers in a typical web app, and they write them faster than anyone can read them. Personal data leaks are a good test of any review process, because the code that causes them looks ordinary. A name is printed, an email is used as a fallback, an attribute gets a longer description.

A language model can review a pull request and flag some of these. A deterministic check answers the same question every time, can fail a build, and gives the same result on Friday evening as on Monday morning. This article describes the design of one, in four guardrails that work together. They are the design behind niji, the PII guardrails for Claude Code and Codex.

## Why searching for strings stops early

The first idea is to search the code for `.email` and `.name`. That finds a lot, and then it misses the cases that matter. The receiver has a different name in every file (user, maker, reviewer, author, a block variable called `it`). A helper takes a person as a parameter and prints a field from it, so the page that calls the helper shows only the helper's name. A model method renames the data, and a view prints the new name.

All three cases share one property. The path from the database column to the screen has several hops, and a search that starts at the screen sees only the last one. Each guardrail below starts from the other end.

## Guardrail one is a declared source

Write down, in one place on the model, which columns identify a person. A constant with two or three names is enough. This list is the only configuration the rest of the system needs, and a new personal column is one edit.

From that list, code can derive more than a person would remember to write. It collects the framework's aliases for the columns. It parses the model and its concerns to find every method that returns one of them, and keeps going until the list stops growing. It reads the other models in the app for methods that hand a personal value along, such as a display name built from the user's name.

## Guardrail two is a trace to every screen

Next, find the receivers that can hold a person. The framework already has that knowledge in its association metadata. Every association whose class is the user model gives a name that people travel under in views. A scope chain that starts at the user class also types its block variable, so a loop over makers is covered.

Then parse everything that reaches a viewer. Templates should be compiled by the framework's own compiler before parsing, so that conditionals around admin-only sections stay in the syntax tree. A helper that reads a personal value from its own parameter is judged at each call site, together with the argument it receives. This one rule found the leak that started this work, a helper that wrote a name and an email into the alt text of every profile picture.

## Guardrail three is a verdict about the viewer

Every read gets a verdict, and the verdict depends on who is looking. A read is safe when it shows viewers their own data. It is safe inside a place only admins reach, which the check can derive from the controllers, because a controller that keeps the default guard serves admins only. It is safe in a mail's own recipient, derived from the mailer action that sends it. Everything else needs a human, and the human writes one sentence in a reviewed file explaining why the read is safe.

The file has three behaviours that keep it honest. An entry that no longer matches any read fails the run, so the list shrinks along with the code. An entry can pin the kind of data it covers, so a read that changes from a name to an email needs a fresh review. A partial template is judged on its own reads, since another controller's page can render it.

## Guardrail four is watching it fail

A check that has only ever passed proves little. Keep the original bugs as test fixtures, so the old leaking line must still be reported. Run the check against the real application as a test, so a new leak fails the normal test run. Then break something deliberately once, such as adding an email fallback to the review's display name, and confirm the run turns red on every page that prints it.

Put the same command in the pipeline your team already uses before a release. A leak reaches production through whichever path skips the check, so a check that lives on one laptop protects one laptop.

## Where this design stops

The trace follows direct reads, helpers that relay a parameter and model methods that hand a value along. A value copied into a local variable and printed later can slip through, and a partial that several pages share usually needs an explained entry. Treat those as the cost of a deterministic tool. Tests on the surfaces where leaks hide, such as alt text and email bodies, cover the remainder.

niji's first version is written for Rails, because Rails exposes association metadata and a template compiler that a script can call. The same four steps carry over to any framework that offers model metadata and a way to parse its templates. The work in a new stack is mostly in the second guardrail.

## A way to start this week

Pick one personal column and trace it by hand from the model to every place it is printed. Write down the five or six different shapes the read takes along the way. Those shapes are the specification of your check, and they are also the list to give an agent when you ask it to build one.
