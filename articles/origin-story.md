---
title: The review email that named the wrong person
date: 20 Oct 2026
subtitle: A one-line leak in a daily email led me to build a check that follows personal data from the model to every screen.
description: How a review email that named another maker led to a check that traces names and emails from the database model to every page, email and image.
badges: [privacy, engineering, rails, ai agents]
---

This week a daily digest email on AI Agents Live told its reader that a maker was waiting for their review. The name in that sentence belonged to someone else, the owner of a listing the email recommended. The email had handed one maker's name to another maker, and neither of them had asked for that.

The fix took a minute. The heading became "A new listing is waiting for your review", and the listing name, which is already public, stayed in the line below it. The more useful question came afterwards. How many other places print one person's details on another person's screen, and could a machine find them every time instead of me remembering to look?

This article is the story of answering that question, including the part where my first answer was incomplete. The answer grew into niji, the PII guardrails for Claude Code and Codex.

## The first answer found the email and missed the real leak

My first attempt was a structural search for the shapes I could think of, such as `maker.name` and `user.email_address`, across the views, mailers and helpers. It found the digest line straight away and listed a few dozen other reads. Almost all of them were fine. They sat on admin pages, or showed people their own details.

Then I asked a language server who calls the method that joins a person's name and email. One of the callers was a helper that draws profile pictures. It used the person's name and email as the picture's alt text, the description that screen readers read aloud and that stays in the page source. That helper ran on every public review page. Anyone with a profile picture who had left a review had their email address sitting in the HTML for any visitor to read.

My search had missed it because the read happened on a plain parameter called `user` inside a helper, a shape I had not written a pattern for. The data had travelled two hops before it reached the page, and I was searching from the page backwards.

## Start at the source instead

The database model already knows which columns identify a person. So I wrote that down once, as a single line on the user model, and let code work out the rest.

From that list the check derives every alias of those columns, and every method on the model that returns them, such as the one that joins name and email. It reads the model's associations to learn which names a person travels under in views (maker, user, author, invited by). It also follows methods on other models that hand a name along. The review model has one, and the check treats it as a source too.

Then it reads every view, mailer, helper, controller and service. Templates are compiled the way Rails compiles them, which keeps an `if admin?` visible to the parser. A helper that reads a person's data from its own parameter is judged at each place that calls it, together with the person it was handed.

## Every read gets a verdict about the viewer

The check asks one question for each read. Does this screen show the viewer something the page already prints for them in plain text? Four answers count as safe.

The first is the viewer's own data. The second is an admin-only place, which the check derives from the controllers themselves, because a controller that keeps the default guard serves only admins. The third is the recipient of a mail, which the check derives from the mailer action that sends it. The fourth is an entry in a short file where a person wrote down, in one sentence, why the read is safe.

Entries in that file can pin what they cover. An entry that says "this is a name" stops matching when the read turns into an email, and an entry whose read has disappeared fails the run until someone removes it. The list keeps itself current.

## What the first complete run showed

With an empty list the check reported a few dozen reads. I opened every one. Forty turned out to be legitimate, and each got its sentence. Seven were the avatar helper.

The fix was to give the picture an empty alt text. A name is printed beside every avatar, so the picture is decoration, and the [W3C guidance on decorative images](https://www.w3.org/WAI/tutorials/images/decorative/) asks for exactly that. It also satisfies the rule I wanted in the first place, that an alt text carries only what the page already shows that viewer.

## A check you have watched fail is one you can trust

The step I trust most came last. I edited the review model on purpose, so a reviewer without a name fell back to their email address. Every review page flipped to exposed, and the run failed. I restored the model and the run went green.

The tests also keep the original digest line and the avatar helper as fixtures, so both leaks stay reproducible even after the fixes.

## A first week for your own app

On the first day, list the columns in your database that identify a person, and put them in one constant on the model. On the second day, write down who may see each kind of page, and look for the controllers that serve admins only. On the third day, write or borrow a check that starts from that list and walks outward to the screens, mails and images.

Spend the fourth day reading every hit and writing one honest sentence for each safe one. On the fifth day, add the check to the command your team already runs before a release, and break it on purpose once to watch it fail. niji is the version of this check that I wanted when I started, so you can begin at the fourth day.
