# Notification Mute/Unmute System - Visual Diagrams

## 1. Complete System Architecture

```mermaid
graph TB
    subgraph "Flutter App"
        A[User Long-Press Channel] --> B[Bottom Sheet]
        B --> C{Mute or Unmute?}
        C -->|Mute| D[NotificationPreferencesService]
        C -->|Unmute| D
        D --> E[Save to SharedPreferences]
        D --> F[Sync to Supabase]
    end
    
    subgraph "Supabase Database"
        F --> G[(notification_preferences table)]
        G --> H[user_id, channel_id, notifications_enabled]
    end
    
    subgraph "Post Creation Flow"
        I[User Creates Post] --> J[Database Trigger]
        J --> K[notify_post_created function]
        K --> L[Call Edge Function]
    end
    
    subgraph "Edge Function"
        L --> M[Get Followers from user_follows]
        M --> N[Query notification_preferences]
        N --> O{Check Each User}
        O -->|Enabled| P[Add to FCM List]
        O -->|Muted| Q[Skip User]
        P --> R[Send Batch to FCM]
    end
    
    subgraph "User Devices"
        R --> S[Device 1: Receives Notification]
        Q --> T[Device 2: No Notification Muted]
    end
    
    E --> U[Update UI Icon]
    U --> V{Show Icon?}
    V -->|Muted| W[Display 🔕]
    V -->|Unmuted| X[No Icon]
    
    style A fill:#e1f5ff
    style G fill:#ffe1e1
    style R fill:#e1ffe1
    style T fill:#ffffe1
    style W fill:#ffd700
```

## 2. User Interaction Flow

```mermaid
sequenceDiagram
    participant User
    participant UI as ChannelsList UI
    participant Service as NotificationPreferencesService
    participant Local as SharedPreferences
    participant Supabase as Supabase DB
    participant EdgeFunc as Edge Function
    
    Note over User,EdgeFunc: MUTING A CHANNEL
    
    User->>UI: Long-press Channel
    UI->>UI: Show Bottom Sheet
    User->>UI: Tap "Mute notifications"
    UI->>Service: toggleChannelNotification(channelId)
    Service->>Local: Save preference locally
    Local-->>Service: ✓ Saved
    Service->>Supabase: Upsert to notification_preferences
    Supabase-->>Service: ✓ Synced
    Service-->>UI: Update complete
    UI->>UI: Show snackbar "Muted"
    UI->>UI: Display 🔕 icon
    
    Note over User,EdgeFunc: NEW POST CREATED
    
    User->>EdgeFunc: Create post in muted channel
    EdgeFunc->>Supabase: Get followers
    Supabase-->>EdgeFunc: 10 followers
    EdgeFunc->>Supabase: Get notification_preferences
    Supabase-->>EdgeFunc: 1 user muted
    EdgeFunc->>EdgeFunc: Filter: 9 enabled, 1 muted
    EdgeFunc->>User: Send to 9 devices only
    Note over User: Muted user doesn't receive notification
```

## 3. Database Schema & Relationships

```mermaid
erDiagram
    USER_PROFILES ||--o{ NOTIFICATION_PREFERENCES : has
    ORGANIZATIONS ||--o{ NOTIFICATION_PREFERENCES : has
    USER_FOLLOWS ||--o{ NOTIFICATION_PREFERENCES : "preference for"
    POSTS ||--o{ NOTIFICATION_LOGS : triggers
    
    USER_PROFILES {
        uuid id PK
        text full_name
        text fcm_token
    }
    
    ORGANIZATIONS {
        uuid id PK
        text name
        text logo_url
    }
    
    NOTIFICATION_PREFERENCES {
        uuid id PK
        uuid user_id FK
        uuid channel_id FK
        boolean notifications_enabled
        timestamp created_at
        timestamp updated_at
    }
    
    USER_FOLLOWS {
        uuid user_id FK
        uuid organization_id FK
    }
    
    POSTS {
        uuid id PK
        uuid organization_id FK
        uuid created_by FK
        text content
    }
    
    NOTIFICATION_LOGS {
        uuid id PK
        uuid post_id FK
        uuid channel_id FK
        int recipient_count
        int success_count
        int failure_count
    }
```

## 4. Edge Function Logic Flow

```mermaid
flowchart TD
    A[Edge Function Triggered] --> B[Parse Request: postId, channelId, title, body]
    B --> C[Query user_follows for channelId]
    C --> D{Followers Found?}
    D -->|No| E[Return: No followers to notify]
    D -->|Yes| F[Extract user_ids from followers]
    F --> G[Query notification_preferences<br/>WHERE channel_id = channelId<br/>AND user_id IN user_ids]
    G --> H[Create preferences Map]
    H --> I{For Each Follower}
    I --> J{Check Preference}
    J -->|Not in map| K[Default: ENABLED]
    J -->|In map: true| K
    J -->|In map: false| L[SKIP - Muted]
    K --> M[Add FCM token to list]
    L --> N[Add to skipped list]
    M --> O[Continue loop]
    N --> O
    O --> I
    I -->|All processed| P[Log: X enabled, Y muted]
    P --> Q{FCM tokens empty?}
    Q -->|Yes| R[Return: No tokens to send]
    Q -->|No| S[Build FCM message payload]
    S --> T[Send to FCM API]
    T --> U[Insert into notification_logs]
    U --> V[Return success]
    
    style E fill:#ffe1e1
    style L fill:#ffffe1
    style M fill:#e1ffe1
    style V fill:#e1f5ff
```

## 5. Testing Flow Diagram

```mermaid
graph LR
    subgraph "Setup Phase"
        A1[Run notification_preferences_schema.sql] --> A2[Deploy Edge Function]
        A2 --> A3[Add syncFromSupabase on login]
    end
    
    subgraph "Test 1: Mute Channel"
        B1[Open App] --> B2[Long-press Channel A]
        B2 --> B3[Tap 'Mute notifications']
        B3 --> B4{Icon visible?}
        B4 -->|Yes ✓| B5[Check Database]
        B4 -->|No ✗| B6[Debug: Check _loadNotificationState]
        B5 --> B7{Row exists with enabled=false?}
        B7 -->|Yes ✓| B8[Test 1 PASS]
        B7 -->|No ✗| B9[Debug: Check Supabase sync]
    end
    
    subgraph "Test 2: Verify No Notification"
        C1[Use Account 2] --> C2[Create Post in Channel A]
        C2 --> C3{Account 1 receives notification?}
        C3 -->|No ✓| C4[Check Edge Function Logs]
        C3 -->|Yes ✗| C5[Debug: Check Edge Function filtering]
        C4 --> C6{Log shows 'Skipping user'?}
        C6 -->|Yes ✓| C7[Test 2 PASS]
        C6 -->|No ✗| C8[Debug: Edge Function not filtering]
    end
    
    subgraph "Test 3: Unmute Channel"
        D1[Long-press Channel A again] --> D2[Tap 'Unmute notifications']
        D2 --> D3{Icon removed?}
        D3 -->|Yes ✓| D4[Create another post]
        D3 -->|No ✗| D5[Debug: Check setState]
        D4 --> D6{Notification received?}
        D6 -->|Yes ✓| D7[Test 3 PASS]
        D6 -->|No ✗| D8[Debug: Check FCM token]
    end
    
    A3 --> B1
    B8 --> C1
    C7 --> D1
    
    style B8 fill:#90EE90
    style C7 fill:#90EE90
    style D7 fill:#90EE90
    style B6 fill:#FFB6C1
    style B9 fill:#FFB6C1
    style C5 fill:#FFB6C1
    style C8 fill:#FFB6C1
    style D5 fill:#FFB6C1
    style D8 fill:#FFB6C1
```

## 6. State Transitions

```mermaid
stateDiagram-v2
    [*] --> New_Channel: User follows channel
    New_Channel --> Enabled: Default state (notifications ON)
    
    Enabled --> Muting: User long-press → Mute
    Muting --> Local_Save: Save to SharedPreferences
    Local_Save --> Supabase_Sync: Upsert to DB
    Supabase_Sync --> Muted: Show 🔕 icon
    
    Muted --> Unmuting: User long-press → Unmute
    Unmuting --> Local_Update: Update SharedPreferences
    Local_Update --> Supabase_Update: Upsert enabled=true
    Supabase_Update --> Enabled: Remove icon
    
    Muted --> Post_Created: New post
    Post_Created --> Edge_Check: Edge Function checks preference
    Edge_Check --> Skip_Notification: enabled=false
    Skip_Notification --> Muted
    
    Enabled --> Post_Created2: New post
    Post_Created2 --> Edge_Check2: Edge Function checks preference
    Edge_Check2 --> Send_Notification: enabled=true or no preference
    Send_Notification --> Enabled
    
    note right of Muted
        - 🔕 icon visible
        - No notifications received
        - Preference in DB: enabled=false
    end note
    
    note right of Enabled
        - No icon
        - Notifications received
        - Preference in DB: enabled=true or missing
    end note
```

## 7. Complete Testing Checklist

```mermaid
flowchart TD
    Start([Start Testing]) --> Setup{Database Setup Complete?}
    Setup -->|No| S1[Run notification_preferences_schema.sql]
    S1 --> Setup
    Setup -->|Yes| Step1[Step 1: Test Mute]
    
    Step1 --> T1_1[Long-press channel]
    T1_1 --> T1_2[Tap Mute notifications]
    T1_2 --> T1_3{Snackbar shown?}
    T1_3 -->|No| Fail1[❌ FAIL: Check UI implementation]
    T1_3 -->|Yes| T1_4{Icon 🔕 visible?}
    T1_4 -->|No| Fail2[❌ FAIL: Check _isNotificationEnabled state]
    T1_4 -->|Yes| T1_5[Query database]
    T1_5 --> T1_6{notifications_enabled = false?}
    T1_6 -->|No| Fail3[❌ FAIL: Check Supabase sync]
    T1_6 -->|Yes| Pass1[✅ PASS: Mute works]
    
    Pass1 --> Step2[Step 2: Test Notification Filtering]
    Step2 --> T2_1[Use second account]
    T2_1 --> T2_2[Create post in muted channel]
    T2_2 --> T2_3{First account gets notification?}
    T2_3 -->|Yes| Fail4[❌ FAIL: Check Edge Function]
    T2_3 -->|No| T2_4[Check Edge Function logs]
    T2_4 --> T2_5{Log shows skip message?}
    T2_5 -->|No| Fail5[❌ FAIL: Edge Function not deployed]
    T2_5 -->|Yes| Pass2[✅ PASS: Filtering works]
    
    Pass2 --> Step3[Step 3: Test Unmute]
    Step3 --> T3_1[Long-press same channel]
    T3_1 --> T3_2[Tap Unmute notifications]
    T3_2 --> T3_3{Icon removed?}
    T3_3 -->|No| Fail6[❌ FAIL: Check state refresh]
    T3_3 -->|Yes| T3_4[Create another post]
    T3_4 --> T3_5{Notification received?}
    T3_5 -->|No| Fail7[❌ FAIL: Check FCM setup]
    T3_5 -->|Yes| Pass3[✅ PASS: Unmute works]
    
    Pass3 --> Step4[Step 4: Test Cross-Device Sync]
    Step4 --> T4_1[Logout and login]
    T4_1 --> T4_2{syncFromSupabase called?}
    T4_2 -->|No| Fail8[❌ FAIL: Add sync on login]
    T4_2 -->|Yes| T4_3{Mute state preserved?}
    T4_3 -->|No| Fail9[❌ FAIL: Check sync implementation]
    T4_3 -->|Yes| Pass4[✅ PASS: Sync works]
    
    Pass4 --> Complete([🎉 All Tests Passed!])
    
    style Pass1 fill:#90EE90
    style Pass2 fill:#90EE90
    style Pass3 fill:#90EE90
    style Pass4 fill:#90EE90
    style Complete fill:#FFD700
    style Fail1 fill:#FFB6C1
    style Fail2 fill:#FFB6C1
    style Fail3 fill:#FFB6C1
    style Fail4 fill:#FFB6C1
    style Fail5 fill:#FFB6C1
    style Fail6 fill:#FFB6C1
    style Fail7 fill:#FFB6C1
    style Fail8 fill:#FFB6C1
    style Fail9 fill:#FFB6C1
```

## 8. Data Flow Timeline

```mermaid
timeline
    title Notification Preference Lifecycle
    
    section User Action
        T=0s : User long-presses channel
        T=0.1s : Bottom sheet appears
        T=0.5s : User taps "Mute"
    
    section Local Storage
        T=0.6s : Save to SharedPreferences
        T=0.7s : Update UI state (_isNotificationEnabled = false)
        T=0.8s : Show 🔕 icon
        T=0.9s : Display snackbar
    
    section Supabase Sync
        T=1.0s : Async call to Supabase
        T=1.2s : Upsert to notification_preferences table
        T=1.3s : Database updated (user_id, channel_id, enabled=false)
        T=1.4s : Sync complete
    
    section Post Creation
        T=60s : Another user creates post in channel
        T=60.1s : Database trigger fires
        T=60.2s : Edge Function called
    
    section Edge Function Processing
        T=60.3s : Query user_follows (10 followers)
        T=60.4s : Query notification_preferences
        T=60.5s : Filter results (9 enabled, 1 muted)
        T=60.6s : Build FCM payload for 9 users
        T=60.7s : Send to FCM
    
    section Delivery
        T=61s : 9 users receive notification
        T=61s : 1 user (muted) receives nothing
        T=61.2s : Log inserted to notification_logs
```

## 9. Troubleshooting Decision Tree

```mermaid
graph TD
    Problem{What's not working?}
    
    Problem -->|Icon not showing| P1{Snackbar appeared?}
    P1 -->|No| S1[Check onLongPress is wired]
    P1 -->|Yes| P1a{Check setState called?}
    P1a -->|No| S2[Verify mounted check]
    P1a -->|Yes| S3[Add debug: print _isNotificationEnabled]
    
    Problem -->|Still getting notifications| P2{Check database}
    P2 --> P2a{Row exists in notification_preferences?}
    P2a -->|No| S4[Check _syncPreferenceToSupabase]
    P2a -->|Yes| P2b{notifications_enabled = false?}
    P2b -->|No| S5[Check toggle logic]
    P2b -->|Yes| P2c{Check Edge Function logs}
    P2c --> S6[Look for 'Skipping user' message]
    
    Problem -->|Preferences not syncing| P3{User logged in?}
    P3 -->|No| S7[Login required]
    P3 -->|Yes| P3a{Internet connected?}
    P3a -->|No| S8[Check network]
    P3a -->|Yes| P3b{Check Supabase logs}
    P3b --> S9[Look for RLS policy errors]
    
    Problem -->|Cross-device not working| P4{syncFromSupabase called?}
    P4 -->|No| S10[Add to login flow]
    P4 -->|Yes| P4a{Check returned data}
    P4a --> S11[Query notification_preferences directly]
    
    style S1 fill:#FFE4B5
    style S2 fill:#FFE4B5
    style S3 fill:#FFE4B5
    style S4 fill:#FFE4B5
    style S5 fill:#FFE4B5
    style S6 fill:#FFE4B5
    style S7 fill:#FFE4B5
    style S8 fill:#FFE4B5
    style S9 fill:#FFE4B5
    style S10 fill:#FFE4B5
    style S11 fill:#FFE4B5
```

---

## Quick Reference Commands

```bash
# Setup
cd supabase
supabase sql < notification_preferences_schema.sql
supabase functions deploy send-fcm-notification

# Check database
SELECT * FROM notification_preferences WHERE user_id = auth.uid();

# View logs
supabase functions logs send-fcm-notification --tail

# Test query
SELECT 
  up.full_name,
  o.name as channel,
  np.notifications_enabled
FROM notification_preferences np
JOIN user_profiles up ON np.user_id = up.id
JOIN organizations o ON np.channel_id = o.id
WHERE np.user_id = auth.uid();
```
