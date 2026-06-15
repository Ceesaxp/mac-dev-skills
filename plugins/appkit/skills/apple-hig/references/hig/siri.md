---
url: "https://developer.apple.com/design/human-interface-guidelines/siri"
title: "Siri | Apple Developer Documentation"
---

# Siri

People use Siri to help them with the things they need to find, know, or do every day.

![A sketch of the Siri icon. The image is overlaid with rectangular and circular grid lines and is tinted blue to subtly reflect the blue in the original six-color Apple logo.](https://docs-assets.developer.apple.com/published/8e1b9efe67353bcd04df47749fb03905/technologies-Siri-intro%402x.png)

Siri is a personal assistant that helps people get information and perform quick actions throughout the system and the apps they use. People interact with Siri in a variety of ways, like using their voice, swiping down from the Dynamic Island, or in the Siri app.

On supported devices, Siri AI introduces a version of Siri powered by Apple Intelligence. When an app integrates its content and features with Apple Intelligence, people can use the natural language awareness and contextual understanding of Siri to initiate the app’s actions from anywhere in the system, interact with content on screen, and quickly reach features that would otherwise require navigating deep into the app.

For example, someone can say “Send a message to Marisa in _AppName_” from anywhere in the system, and Siri can help them complete that task in a contextually appropriate way. With a photo visible on screen, someone can say “Add this photo to my Landscapes album,” then follow up with “And email it to Josh,” which opens an email compose view and adds Josh as the recipient. Saying “Make this black and white” to convert an image to grayscale can also be faster than navigating through menus to find the same command.

## Getting your app to work with Siri

By default, the system doesn’t have specific awareness of what an app can do or the information it contains. In order for an app to work with Siri, the app has to make its features and content available to Apple Intelligence using the [App Intents](https://developer.apple.com/documentation/AppIntents) framework.

When an app implements intents, the system can expose the things the app can do (the app’s actions, or _intents_) and its content (the app’s _entities_) in system experiences where it makes sense. This makes the app’s actions and content available to features that build on Apple Intelligence, such as Siri, Spotlight, and the Shortcuts app. For developer guidance, see [Getting started with the App Intents framework](https://developer.apple.com/documentation/AppIntents/getting-started-with-the-app-intents-framework).

To get the most out of Siri, an app can additionally associate its features and content with app _[schemas](https://developer.apple.com/documentation/AppIntents/app-schema-domains)_: preset templates for functionality that the system already understands. Apps in common domain areas like email, music, or photos can use the system’s existing knowledge to access built-in logic for handling requests through a wider range of options with natural conversation and deeper contextual understanding. For developer guidance, see [Apple Intelligence and Siri AI](https://developer.apple.com/documentation/AppIntents/apple-intelligence-and-siri-ai) and [Making actions and content discoverable by Apple Intelligence](https://developer.apple.com/documentation/AppIntents/making-actions-and-content-discoverable-by-apple-intelligence).

### Sharing contextual information

In addition to exposing actions and content with schemas, an app can offer a more personalized experience by giving the system contextual information about its content and features.

An app can tell the system what’s onscreen by annotating its views and other content with app entities. This gives the system information Siri needs to improve contextual interaction based on what someone is interacting with. For example, when someone refers to parts of your app’s content (like buttons or onscreen graphics) during a Siri conversation, Siri can use the annotations your app provides to understand what the person means. For developer guidance, see [Providing contextual cues to Apple Intelligence and Siri](https://developer.apple.com/documentation/AppIntents/providing-contextual-cues-to-apple-intelligence-and-siri).

To provide content information to the system, an app can donate entities to the on-device Spotlight index, which makes the app’s information available to someone searching in Spotlight or with Siri. For developer guidance, see [Defining app entities for your custom data types](https://developer.apple.com/documentation/AppIntents/defining-app-entities-for-your-custom-data-types) and [Making app entities available in Spotlight](https://developer.apple.com/documentation/AppIntents/making-app-entities-available-in-spotlight).

An app can also tell the system about actions a person takes while using it by donating the actions as intents. This helps Siri anticipate future actions a person might want to take, and surface them through various system experiences at appropriate times. Examples of actions an app can donate include things like a person’s recent activity or items that a person has indicated an interest in. For developer guidance, see [Donating your app’s data and actions to the system](https://developer.apple.com/documentation/AppIntents/donating-your-apps-data-and-actions-to-the-system).

## Best practices

**Identify your app’s most popular actions, and when and where they occur.** Understanding the contexts where those actions are relevant, such as in a hands-free environment or on a particular device, can help you prioritize which actions and content to expose as app intents and entities, and inform how you design a great Siri experience.

**Use familiar terms for your content and actions.** When you create an app intent or entity, you choose the terminology that represents it. For example, you could refer to an audio file as a track, a song, or a podcast. Using language for your features and content that people are most likely to recognize makes interacting with your app through Siri more natural and intuitive.

**Offer relevant content.** Instead of telling Spotlight about all of your app’s content, consider things that are particularly relevant to someone’s personal context — things they’ve recently searched for, their favorite items or bookmarks, or the content of a wishlist. Some app categories, like email or messaging, might have a good reason to consider their entire catalog as relevant information; it can be appropriate to provide expanded access in those cases.

**Don’t advertise.** Don’t include advertisements, marketing, or in-app purchase sales pitches in content that Siri delivers.

**Only provide a custom response if built-in responses don’t meet your app’s needs.** Siri is designed to anticipate a wide variety of natural language requests and respond helpfully without additional configuration.

## Customizing your app’s experience with Siri

For apps with many common feature sets, existing [app schema domains](https://developer.apple.com/documentation/AppIntents/app-schema-domains) provide the built-in functionality that they need to expose their actions and content to Apple Intelligence and Siri without any additional work. If your app’s functionality falls outside of these areas, _App Shortcuts_ offer a way to expose custom actions to the system for Siri to access. For design guidance, see [App Shortcuts](app-shortcuts.md). For developer guidance, see [App Shortcuts](https://developer.apple.com/documentation/AppIntents/app-shortcuts).

To customize the experience of an action or a piece of content associated with an existing schema, an app can define additional optional properties as part of an intent or entity that can contextually enhance the response that Siri provides. An app could present a playback control [snippet](https://developer.apple.com/design/Human-Interface-Guidelines/snippets) that Siri can display as an audio file plays, for example. For developer guidance, see [Displaying static and interactive snippets](https://developer.apple.com/documentation/AppIntents/displaying-static-and-interactive-snippets).

When you provide additional custom properties as part of your schema responses, consider the following guidelines.

**Write response dialogue that’s clear and descriptive.** An effective response clearly conveys what happens when Siri performs the action. If you ask follow-up questions, be sure to customize the default dialogue for clarity. For example, “Which soup?” is clearer than “Which one?”

**Keep responses as succinct as possible.** People might interact with Siri frequently, so they may hear the same response multiple times when answering follow-up questions or dealing with errors. Use the context of the current conversation to remove as many details as possible. Avoid including unnecessary words or attempts at humor, because both can become irritating over time.

**Provide responses that Siri can deliver audibly and visually.** This lets Siri decide which communication method works best for the current situation. For example, if someone using iPhone asks for the weather, the forecast appears onscreen; if they’re using AirPods, Siri speaks the forecast instead. Make sure the voice response can stand alone and that it doesn’t depend on visual elements to fill in essential information.

**Design inclusive interactions.** Create welcoming interactions for everyone by avoiding specific pronouns when they’re not necessary. For example, in response to “Send a message to my best friend,” instead of saying “What’s his or her name?” say “Who should I send it to?” or “To who?” For guidance, see [Writing](writing.md) and [Inclusion](inclusion.md).

**Ask an open-ended question when the full list of options is too long.** If the full list of options is too long for Siri to read in a timely way, follow up with an open-ended question to narrow the scope or get additional detail. For example, “What kind of shoes are you interested in?” in response to a request for the available shoes in a shopping app.

**Keep responses device-independent whenever possible.** People can initiate a Siri request on one device and have it take effect on another, so device-specific wording can easily become confusing or misleading. If you must reference a specific device in a response, make sure it’s accurate and makes sense in context.

**Omit your app name from responses.** The system already provides verbal and visual attribution for your app when responding to people.

**Use appropriate language and respect parental controls.** Don’t include offensive language in dialogue text that you provide. Many families use parental controls to restrict explicit content and other material that’s based on specific rating levels. Be aware that Siri may also respond aloud, and others nearby might hear the response.

**Help people understand errors and failures.** The system provides some default error descriptions, but it’s best to enhance error responses so that they’re specific to the current situation. For example, if the chicken noodle soup is sold out, an error like “Sorry, we’re out of chicken noodle soup” is much clearer than “Sorry, we can’t complete your order.”

## Editorial guidelines

**Refer to Siri by name.** Don’t reference Siri using pronouns like _she_, _him_, or _her_. Ideally, just use the word _Siri_. For example, “After you add a shortcut to Siri, you can run the shortcut anytime by asking Siri.” For additional guidance, see [Guidelines for Using Apple Trademarks](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html).

**Be aware that the system reserves important actions and phrases for Siri.** Never impersonate Siri, attempt to reproduce the functionality that Siri provides, or provide a response that appears to come from Apple. Don’t use reserved phrases like “Call 911” or “Hey Siri.”

**In a localized context, translate only the word _Hey_ in the phrase “Hey Siri.”** As an Apple trademark, _Siri_ is never translated. Here is a list of acceptable translations for the phrase “Hey Siri”:

| Locale code | “Hey Siri” translation | Locale code | “Hey Siri” translation |
| --- | --- | --- | --- |
| ar\_AE | يا Siri | fr\_CA | Dis Siri |
| ar\_SA | يا Siri | fr\_CH | Dis Siri |
| da\_DK | Hej Siri | fr\_FR | Dis Siri |
| de\_AT | Hey Siri | it\_CH | Ehi Siri |
| de\_CH | Hey Siri | it\_IT | Ehi Siri |
| de\_DE | Hey Siri | ja\_JP | Hey Siri |
| en\_AU | Hey Siri | ko\_KR | Siri야 |
| en\_CA | Hey Siri | ms\_MY | Hai Siri |
| en\_GB | Hey Siri | nb\_NO | Hei Siri |
| en\_IE | Hey Siri | nl\_BE | Hé, Siri |
| en\_IN | Hey Siri | nl\_NL | Hé Siri |
| en\_NZ | Hey Siri | no\_NO | Hei Siri |
| en\_SG | Hey Siri | pt\_BR | E aí Siri |
| en\_US | Hey Siri | ru\_RU | привет Siri |
| en\_ZA | Hey Siri | sv\_SE | Hej Siri |
| es\_CL | Oye Siri | th\_TH | หวัดดี Siri |
| es\_ES | Oye Siri | tr\_TR | Hey Siri |
| es\_MX | Oye Siri | zh\_CN | 嘿Siri |
| es\_US | Oye Siri | zh\_HK | 喂 Siri |
| fi\_FI | Hei Siri | zh\_TW | 嘿 Siri |
| fr\_BE | Dis Siri |  |  |

## Resources

#### Related

[App Shortcuts](app-shortcuts.md)

[Snippets](snippets.md)

#### Developer documentation

[App Intents](https://developer.apple.com/documentation/AppIntents)

[App schema domains](https://developer.apple.com/documentation/AppIntents/app-schema-domains)

[Apple Intelligence and Siri AI](https://developer.apple.com/documentation/AppIntents/apple-intelligence-and-siri-ai)

#### Videos

[Build intelligent Siri experiences with App Schemas](https://developer.apple.com/videos/play/wwdc2026/240)

[Discover new capabilities in the App Intents framework](https://developer.apple.com/videos/play/wwdc2026/345)

[Explore advanced App Intents features for Siri and Apple Intelligence](https://developer.apple.com/videos/play/wwdc2026/343)

## Change log

| Date | Changes |
| --- | --- |
| June 8, 2026 | Revised for Siri AI. |
| June 5, 2023 | Removed Add to Siri guidance. Added references to the new [App Shortcuts](app-shortcuts.md) page. |
| May 2, 2023 | Consolidated guidance into one page. |
