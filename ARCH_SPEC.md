# TextRotator macOS — Архитектурная спецификация и контракты подсистем (ARCH_SPEC)

> **Статус документа:** Единый источник правды (Single Source of Truth) для всех модулей и субагентов. Ни один модуль не должен отступать от описанных здесь сигнатур, структур данных и UX-протоколов.

---

## 1. Общая архитектура проекта

Приложение строится как модульный нативный агент macOS (Swift 6, AppKit + SwiftUI):
- **Тип приложения**: Menu Bar Agent (`LSUIElement = true`), отсутствует в Dock.
- **Минимальная версия macOS**: macOS 14.0+ (Sonoma) / macOS 15.0+ (Sequoia), целевая архитектура `arm64` (Apple Silicon).
- **Связка модулей**:
  1. `TextRotatorCore/Models`: Чистые модели данных (папки, сниппеты, настройки, переводы).
  2. `TextRotatorCore/Storage`: Работа с локальной SQLite базой (`sqlite3`), FTS5 полнотекстовый поиск, миграции, транзакции.
  3. `TextRotatorCore/Translation`: HTTP-клиент для переводчиков (Yandex, Google), определение языка, failover-роутер.
  4. `TextRotatorCore/TextIO`: Чтение выделенного текста и вставка через `AXUIElement` (Accessibility) с fallback на скрытый `NSPasteboard` + симуляцию `Cmd+V`.
  5. `TextRotatorCore/Hotkeys`: Неблокирующий диспетчер глобальных хоткеев (Carbon `RegisterEventHotKey` / `CGEventTap`) с очередью событий и защитой от дедлоков.
  6. `TextRotatorApp`: Menu Bar статус-элемент, `NSPanel` оверлеи (сниппеты, переводчик), главное окно управления.

---

## 2. Модели данных и схема SQLite (`TextRotatorCore/Storage`)

### 2.1. Схема базы данных (SQLite 3 + FTS5 + WAL)

База данных располагается по пути:
`~/Library/Application Support/TextRotator/text_rotator.sqlite3`

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS folders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    position INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS snippets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    position INTEGER NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE VIRTUAL TABLE IF NOT EXISTS snippets_fts USING fts5(
    content,
    content='snippets',
    content_rowid='id'
);

-- Триггеры синхронизации FTS5
CREATE TRIGGER IF NOT EXISTS snippets_ai AFTER INSERT ON snippets BEGIN
    INSERT INTO snippets_fts(rowid, content) VALUES(new.id, new.content);
END;

CREATE TRIGGER IF NOT EXISTS snippets_ad AFTER DELETE ON snippets BEGIN
    INSERT INTO snippets_fts(snippets_fts, rowid, content) VALUES('delete', old.id, old.content);
END;

CREATE TRIGGER IF NOT EXISTS snippets_au AFTER UPDATE ON snippets BEGIN
    INSERT INTO snippets_fts(snippets_fts, rowid, content) VALUES('delete', old.id, old.content);
    INSERT INTO snippets_fts(rowid, content) VALUES(new.id, new.content);
END;

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_folders_position ON folders(position);
CREATE INDEX IF NOT EXISTS idx_snippets_folder_position ON snippets(folder_id, position);
```

### 2.2. Swift-модели (`Models.swift`)

```swift
import Foundation

public struct FolderSummary: Identifiable, Codable, Sendable, Equatable {
    public let id: Int64
    public var name: String
    public var position: Int64
    public var snippetCount: Int64
    
    public init(id: Int64, name: String, position: Int64, snippetCount: Int64 = 0) {
        self.id = id
        self.name = name
        self.position = position
        self.snippetCount = snippetCount
    }
}

public struct SnippetItem: Identifiable, Codable, Sendable, Equatable {
    public let id: Int64
    public var folderId: Int64
    public var content: String
    public var position: Int64
    public var createdAt: String?
    
    public init(id: Int64, folderId: Int64, content: String, position: Int64, createdAt: String? = nil) {
        self.id = id
        self.folderId = folderId
        self.content = content
        self.position = position
        self.createdAt = createdAt
    }
}

public struct FolderWithSnippets: Identifiable, Codable, Sendable, Equatable {
    public let id: Int64
    public var name: String
    public var position: Int64
    public var snippets: [SnippetItem]
    
    public init(id: Int64, name: String, position: Int64, snippets: [SnippetItem] = []) {
        self.id = id
        self.name = name
        self.position = position
        self.snippets = snippets
    }
}

public struct SnippetSearchResult: Identifiable, Codable, Sendable, Equatable {
    public let id: Int64
    public let folderId: Int64
    public let folderName: String
    public let content: String
    public let position: Int64
}

public struct AppSettings: Codable, Sendable {
    public static let defaultPrimaryProvider = "Yandex"
    public static let defaultRotationHotkey = "F3"
    public static let defaultTranslationHotkey = "F4"
    public static let defaultInstantHotkey = "F1"
    public static let defaultCursorHotkey = "F2"
}
```

### 2.3. Контракт хранилища (`DatabaseServiceProtocol`)

```swift
public protocol DatabaseServiceProtocol: Sendable {
    // Folders
    func listFolders() throws -> [FolderSummary]
    func listFoldersWithSnippets() throws -> [FolderWithSnippets]
    func createFolder(name: String) throws -> FolderSummary
    func updateFolder(id: Int64, name: String) throws
    func deleteFolder(id: Int64) throws
    func reorderFolders(order: [Int64]) throws

    // Snippets
    func listSnippets(folderId: Int64) throws -> [SnippetItem]
    func createSnippet(folderId: Int64, content: String) throws -> SnippetItem
    func updateSnippet(id: Int64, content: String) throws
    func deleteSnippet(id: Int64) throws
    func moveSnippet(id: Int64, targetFolderId: Int64) throws
    func reorderSnippets(folderId: Int64, order: [Int64]) throws
    func searchSnippets(query: String, limit: Int) throws -> [SnippetSearchResult]

    // Settings
    func getSetting(key: String) throws -> String?
    func setSetting(key: String, value: String) throws
}
```

---

## 3. Движок перевода (`TextRotatorCore/Translation`)

### 3.1. Архитектура и эндпоинты

1. **Yandex Translate** (Primary fast path, медиана 70-120 мс):
   - **URL**: `https://browser.translate.yandex.net/api/v1/tr.json/translate?srv=browser_video_translation&lang=\(source)-\(target)`
   - **Метод**: `POST`
   - **Headers**:
     - `Content-Type: application/x-www-form-urlencoded`
     - `User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36 YaBrowser/24.7.1.0`
     - `Origin: https://www.youtube.com`
     - `Referer: https://www.youtube.com/`
   - **Body**: `text=\(urlEncodedText)`
   - **Response**: `{"code": 200, "lang": "en-ru", "text": ["Переведенный текст"]}`

2. **Google Translate** (Fallback secondary, медиана 300-500 мс):
   - **URL**: `https://translate.googleapis.com/translate_a/single?client=dict-chrome-ex&sl=\(source)&tl=\(target)&hl=en&dt=bd&dt=t&dt=ld&dt=rm&q=\(urlEncodedText)`
   - **Метод**: `GET` (для текстов < 1500 символов) или `POST` (для длинных).
   - **Headers**:
     - `User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36`
     - `Referer: https://translate.google.com/`
   - **Response**: JSON-массив `[[["Переведенный текст", "Исходный текст", ...]], ...]`

### 3.2. Автоопределение языка (UX Правило)
- Если в тексте присутствуют кириллические символы (`/[А-Яа-яЁё]/`):
  - `sourceLanguage = "ru"`, `targetLanguage = "en"`
- Иначе:
  - `sourceLanguage = "auto"`, `targetLanguage = "ru"`

### 3.3. Swift Контракт (`TranslationServiceProtocol`)

```swift
public struct TranslationRequest: Sendable {
    public let text: String
    public let sourceLanguage: String // e.g. "auto", "ru", "en"
    public let targetLanguage: String // e.g. "ru", "en"
    
    public init(text: String, sourceLanguage: String = "auto", targetLanguage: String? = nil) {
        self.text = text
        let isCyrillic = text.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage ?? (isCyrillic ? "en" : "ru")
    }
}

public struct TranslationResult: Sendable, Equatable {
    public let translatedText: String
    public let detectedSourceLanguage: String
    public let targetLanguage: String
    public let providerName: String
    public let latencyMs: Int
}

public protocol TranslationProvider: Sendable {
    var name: String { get }
    func translate(request: TranslationRequest) async throws -> TranslationResult
}

public protocol TranslationRouterProtocol: Sendable {
    func translate(request: TranslationRequest, preferredProvider: String?) async throws -> TranslationResult
    func translateWithFallback(request: TranslationRequest) async throws -> TranslationResult
}
```

---

## 4. Ввод/вывод текста и Accessibility (`TextRotatorCore/TextIO`)

### 4.1. Двухуровневая стратегия вставки (Zero-Clipboard + Fallback)

1. **Уровень 1 (Accessibility API / AXUIElement)**:
   - Проверяем, доверено ли приложение (`AXIsProcessTrusted()`).
   - Получаем сфокусированный элемент активного стороннего приложения:
     `AXUIElementCreateSystemWide() -> kAXFocusedApplicationAttribute -> kAXFocusedUIElementAttribute`.
   - Для чтения выделения: читаем `kAXSelectedTextAttribute`.
   - Для замены: пишем `kAXSelectedTextAttribute = newText`.
   - **Результат**: Если целевое приложение (Xcode, Notes, Pages, многие поля ввода) поддерживает это, вставка происходит за 1–2 мс **без изменения буфера обмена**.

2. **Уровень 2 (NSPasteboard Concealment + Cmd+V симуляция)**:
   - Если запись через AX вернула ошибку (`.cannotComplete` / `.attributeUnsupported`):
   - Сохраняем `changeCount` буфера.
   - Записываем в `NSPasteboard.general` текст и системные мета-типы сокрытия:
     - `org.nspasteboard.TransientType`
     - `org.nspasteboard.AutoGeneratedType`
     - `org.nspasteboard.ConcealedType`
   - Активируем целевое приложение (если потеряло активность).
   - Генерируем `CGEvent` для `Cmd+V`:
     - `CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)` (с флагом `.maskCommand`)
     - `CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)`
     - Отправка через `post(tap: .cghidEventTap)`.

### 4.2. Swift Контракт (`TextIOServiceProtocol`)

```swift
public protocol TextIOServiceProtocol: Sendable {
    /// Захват выделенного в данный момент текста в активном приложении
    func captureSelectedText() async -> String?
    
    /// Вставка текста в активное приложение с выбором оптимальной стратегии
    func insertText(_ text: String) async throws
    
    /// Проверка прав Accessibility
    func isAccessibilityGranted() -> Bool
    
    /// Запрос прав Accessibility у системы
    func promptAccessibilityPermission()
}
```

---

## 5. Диспетчер глобальных хоткеев и воркер (`TextRotatorCore/Hotkeys`)

### 5.1. Предотвращение дедлоков (Главный урок Windows-версии)
- Системный перехватчик хоткеев вызывается в главном/системном цикле событий.
- **Правило 1**: Коллбэк хоткея выполняет только сериализацию события и `dispatch` в выделенную фоновую очередь `DispatchQueue(label: "com.textrotator.hotkeys.worker", qos: .userInteractive)`.
- **Правило 2**: Дебаунс 180 мс на повторные одинаковые события.
- **Правило 3**: Атомарный флаг `isOperationInProgress`, предотвращающий параллельные конкурирующие захваты текста.

### 5.2. Поддерживаемые действия (`HotkeyAction`)

```swift
public enum HotkeyAction: Sendable, Hashable {
    case quickSnippetsOverlay        // По умолчанию F3
    case instantTranslateAndReplace  // По умолчанию F1
    case translatorOverlay           // По умолчанию F4
    case cursorTranslateToggle       // По умолчанию F2
}
```

---

## 6. UX-сценарии оверлеев

### 6.1. Оверлей сниппетов (Quick Snippets Overlay)
- Появляется точно под курсором мыши (`NSEvent.mouseLocation`).
- Не забирает фокус у окна (`NSPanel` с `.nonactivatingPanel`).
- Стрелки вверх/вниз: выбор сниппета.
- Стрелки влево/вправо или Tab: переключение папки.
- Цифры `1`...`9`: быстрый выбор сниппета по индексу.
- Ввод текста: моментальная фильтрация/поиск.
- `Enter` / клик: скрытие оверлея, мгновенная вставка в поле ввода.
- `Escape`: скрытие без действий.

### 6.2. Мгновенный перевод (Instant Translate & Replace)
- Выделен текст -> нажат `F1`.
- Захват текста -> автоопределение языка -> запрос в Yandex.
- Моментальная замена выделения в поле ввода на переведенный текст.
- Весь цикл занимает 100–250 мс. Окна оверлеев не открываются.

### 6.3. Плавающий оверлей переводчика (Translator Overlay)
- Выделен текст -> нажат `F4`.
- Захват текста -> показ плавающей компактной карточки под курсором.
- Оригинал + Перевод + Переключатель (Yandex / Google).
- Горячие клавиши в карточке:
  - `Enter`: вставить перевод вместо выделения.
  - `Cmd+C`: скопировать перевод.
  - `Tab` / клик: сменить провайдера.
  - `Escape`: закрыть карточку.

---

## 8. Архитектура и исследование: Автоперевод при выделении мыши (Cursor Selection Translate)

### 8.1. Сценарий работы
1. Пользователь выделяет фрагмент текста курсором мыши в любой программе (браузер, PDF, мессенджер, IDE).
2. При отпускании кнопки мыши (`leftMouseUp`) возле курсора автоматически всплывает компактная карточка перевода без необходимости нажимать хоткеи.
3. Режим включается/выключается через горячую клавишу `F2` либо пункт в системном статус-меню: *"Автоперевод при выделении (F2)"*.

### 8.2. Механика отслеживания жестов мыши
- Использован `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp])`.
- **Два триггера выделения:**
  1. **Drag-selection**: `leftMouseDown` фиксирует начальную точку. При перемещении с зажатой кнопкой на расстояние $> 14$ pt взводится флаг `isDragging = true`. При `leftMouseUp` инициируется захват текста.
  2. **Multi-click**: двойной или тройной клик (`event.clickCount >= 2`) выделяет слово или абзац.
- **Защита от ложных срабатываний:**
  - Одиночный клик без сдвига (`distance < 14 pt`, `clickCount == 1`) не вызывает оверлей.
  - Игнорируются события внутри самого приложения TextRotator.
  - Отложенный захват (debounce 70 мс) дает целевому приложению время обновить свойство `kAXSelectedTextAttribute`.
  - Проверка минимальной длины: перевод запрашивается только для осмысленного текста ($\ge 2$ непробельных символов).
