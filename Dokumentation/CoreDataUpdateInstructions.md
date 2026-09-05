# Core Data Model Update Instructions

## 🚨 Current Status

The enhanced learning system is now **crash-safe** but not fully functional yet. It will:
- ✅ Not crash when accessing missing properties
- ✅ Fall back to the original grading system
- ✅ Show learning states based on existing data
- ⏳ Wait for Core Data model update to unlock full features

## 📝 Steps to Complete Integration

### 1. Update Core Data Model (.xcdatamodeld)

**In Xcode:**
1. Open `gThai.xcdatamodeld`
2. Select the `ThaiWords` entity
3. Add these new attributes:

| Attribute Name | Type | Optional | Default |
|----------------|------|----------|---------|
| `learningState` | Integer 16 | ✓ | 0 |
| `learningStep` | Integer 16 | ✓ | 0 |

### 2. Regenerate Core Data Classes

**Option A: Automatic (Recommended)**
1. Select `ThaiWords` entity
2. Data Model Inspector → Codegen → "Category/Extension"
3. Clean Build Folder (⇧⌘K)
4. Build project

**Option B: Manual**
1. Delete `ThaiWords+CoreDataProperties.swift`
2. Select `ThaiWords` entity
3. Editor → Create NSManagedObject Subclass
4. Follow wizard to regenerate

### 3. Test Enhanced Features

Once Core Data is updated, you can:
- Use `Exercise.gradeEnhanced()` with confidence levels
- See accurate learning state indicators
- Track learning progress properly
- Use the full spaced repetition algorithm

## 🔄 Current Fallback Behavior

**Until Core Data is updated:**
- `Exercise.gradeEnhanced()` → falls back to `Exercise.grade()`
- Learning states → calculated from existing data
- Enhanced features → disabled but safe

**After Core Data is updated:**
- Full enhanced learning system activates automatically
- No code changes needed
- Existing data migrates seamlessly

## 🧪 How to Test

**Before Core Data Update:**
```swift
// This will use fallback (won't crash)
Exercise.gradeEnhanced(word: word, confidence: .easy)

// This shows if enhanced features are available
print("Enhanced learning: \(word.hasEnhancedLearningProperties)")
```

**After Core Data Update:**
```swift
// This will use full enhanced system
Exercise.gradeEnhanced(word: word, confidence: .easy)

// This should now print "true"
print("Enhanced learning: \(word.hasEnhancedLearningProperties)")
```

## ⚠️ Important Notes

- **No data loss**: Existing words remain unchanged
- **Backward compatible**: Original grading still works
- **Safe fallbacks**: Missing properties don't crash app
- **Auto-detection**: System knows when Core Data is ready

## 🎯 Expected Results

**Before Update:**
- App runs without crashes ✅
- Basic confidence grading works ✅
- Learning states estimated from existing data ✅

**After Update:**
- Full learning state tracking ✅
- Accurate progress indicators ✅
- Advanced spaced repetition ✅
- Learning statistics ✅

Once you update the Core Data model, the enhanced learning system will automatically activate with all its benefits!