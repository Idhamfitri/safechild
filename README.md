# safechild

A new Flutter project.

## What Is This Project About?

SafeChild is an Android parental control application that helps parents in Malaysia protect their children from cyberbullying and harmful content on social media. Unlike basic parental control tools, SafeChild can read what children actually type and receive across apps like WhatsApp, Instagram, TikTok, and Telegram using the Android Accessibility Service. It uses a hybrid two-stage detection approach. Text is first analysed on the device using a traditional Machine Learning classifier, and only unclear results are passes to Gemini AI in the cloud for a deeper check. This keeps API costs low while maintaining strong detection accuracy for English, Malay, and Manglish content.

The application also prevents children from uninstalling or disabling it by detecting system settings access and blocking it using Android Device Policy Manager. When harmful content or a bypass attempt is detected, the parent receives an instant push notification through Firebase Cloud Messaging, triggered automatically by Firebase Cloud Functions without needing a dedicated server. Additional features include screen time scheduling, remote device locking, and a simple pairing code system to link parent and child accounts. Built using Flutter, Firebase, AndroidAPI and Gemini AI, SafeChild provides Malaysian families with an affordable and practical solution for keeping children safe online.
