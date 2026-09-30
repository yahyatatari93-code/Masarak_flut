importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js");

const firebaseConfig = {
  apiKey: "AIzaSyAvWIuwqNxsk_H28fOTcz4cyWIvk8e0F6o",
  authDomain: "masarak-5f47d.firebaseapp.com",
  projectId: "masarak-5f47d",
  storageBucket: "masarak-5f47d.firebasestorage.app",
  messagingSenderId: "986184003003",
  appId: "1:986184003003:web:1a44a055b97903e225a89e"
};

// تهيئة فايربيس
firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();

// استقبال الإشعارات في الخلفية
messaging.onBackgroundMessage(function(payload) {
  console.log("تم استقبال إشعار في الخلفية: ", payload);
  const notificationTitle = payload.notification?.title || 'إشعار من مسارك';
  const notificationOptions = {
    body: payload.notification?.body || 'تحديث جديد من الحافلة',
    icon: '/icons/Icon-192.png'
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
