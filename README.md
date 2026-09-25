# safechild

A cutting-edge, hybrid parental control application built with Flutter to protect children in Malaysia from cyberbullying and harmful social media content.

[![Watch SafeChild Demo Video](https://youtube.com)](https://youtu.be/Cg7P7EzuDNQ)

---

## 📌 Project Overview

**SafeChild** is an advanced Android parental control solution designed specifically for the Malaysian cultural and linguistic landscape. Unlike basic content filters, SafeChild actively monitors on-screen text and inputs across popular applications—including **WhatsApp, Instagram, TikTok, and Telegram**—by leveraging the Android Accessibility Service.

### 🧠 Hybrid Multi-Stage Detection
To ensure enterprise-grade accuracy without skyrocketing infrastructure costs, SafeChild features a unique two-stage analysis pipeline:
1. **On-Device Machine Learning:** Local classifiers instantly screen text for immediate red flags.
2. **Cloud-Based Gemini AI:** Ambigious or highly nuanced text is passed to the cloud for deeper contextual analysis. 

This architecture maintains unmatched accuracy across **English, Malay, and Manglish** (Malaysian English) content while keeping API overhead exceptionally low.

---

## ✨ Core Features

* **Advanced Cross-App Monitoring:** Tracks incoming and outgoing text across major social platforms via Android Accessibility Service.
* **Tamper-Proof Protection:** Utilizes the Android Device Policy Manager to block unauthorized access to system settings, preventing children from disabling or uninstalling the app.
* **Serverless Alerts:** Instantly routes push notifications to parents via **Firebase Cloud Functions** and **Firebase Cloud Messaging (FCM)** without requiring a dedicated backend server.
* **Device Control Tools:** Seamless screen time scheduling and remote device locking capabilities.
* **Effortless Setup:** Simple, secure pairing-code system to instantly link parent and child devices.

---

## 🛠️ Built With

* **Frontend Framework:** Flutter (Dart)
* **Cloud Infrastructure:** Firebase (Cloud Functions, Cloud Messaging, Firestore)
* **Intelligence Engines:** Android Native ML Classifiers & Gemini AI API
* **OS Integrations:** Android API (Accessibility Service, Device Policy Manager)

---

## 🚀 Getting Started

### Prerequisites
* Flutter SDK (Latest Stable Version)
* Android Studio / Android SDK (Target API 30+)
* A Firebase Project setup with Cloud Functions enabled
* Google Gemini API Key

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com
   cd safechild
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure Environment:**
   * Add your `google-services.json` to the `android/app/` directory.
   * Add your Gemini API key to your environment variables or local configuration file.

4. **Run the application:**
   ```bash
   flutter run
   ```practical solution for keeping children safe online.


<img width="955" height="532" alt="Screenshot 2026-06-06 121211" src="https://github.com/user-attachments/assets/0bc353ce-e092-4235-8cf4-5b43f3281da3" />
<img width="1169" height="608" alt="Screenshot 2026-06-06 123407" src="https://github.com/user-attachments/assets/21cc7a67-eb97-41ef-a831-4b61b0d293d4" />
<img width="1169" height="654" alt="Screenshot 2026-06-06 123433" src="https://github.com/user-attachments/assets/ca7e2b9b-8db5-42e4-8c47-2566b626d804" />
<img width="1173" height="660" alt="Screenshot 2026-06-06 123800" src="https://github.com/user-attachments/assets/a2bf0a8c-a3a3-4dd9-b39b-3f135f2c5ae7" />
