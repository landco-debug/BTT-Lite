> **УСТАРЕВШАЯ ПОСТАНОВКА ЗАДАЧИ. TP10, 27.09.2026:** пользователь уточнил, что двойной тап должен скрывать приложение, над ОКНОМ которого находится указатель. Наведение на Dock не требуется. См. agents.md → TP10 и experiments/trickpad-pilot/README.md. Нижеследующий текст сохранён только как история ошибочного направления диагностики.

# HANDOFF — Trickpad Pilot TP08: нерешённый 3-finger double-tap по Dock

Дата: 2026-09-27  
Репозиторий: `landco-debug/BTT-Lite`  
Рабочая ветка: `trickpad-pilot`  
Текущий базовый билд: **TP08**  
Коммит реализации TP08: `325e00e580b26ba87294d928d5eb65a3f4eb2b2f`  
Коммит фиксации TP08 в hand-off: `7f10b328e1632e64fb7d77d3522bd5903463a4b5`  
Upstream Trickpad: `nweii/trickpad` 0.14.0, pinned commit `e16f7fcd1613b9df944957cbda0e69d8eaf19163`

## 1. Контекст и цель

Пользователь тестирует **обычный upstream Trickpad 0.14.0** как лёгкую замену части BetterTouchTool на MacBook Air M1 / macOS Sequoia. Сам Trickpad пока не форкается и не модифицируется. Всё дополнительное реализовано только короткоживущим helper-бинарником и TOML-конфигурацией.

Цель пилота — воспроизвести ровно текущие пользовательские жесты BTT с минимальным расходом ресурсов.

## 2. Зафиксированные жесты

### Magic Mouse — 3

- 3 Finger Swipe Up → ⇧⌘T
- 3 Finger Swipe Down → ⌘W
- 3 Finger Click → ⇧⌘V

### Встроенный Trackpad — 6

- 3 Finger Click → ⇧⌘V
- 3 Finger Swipe Up → ⇧⌘T
- 3 Finger Swipe Down → ⌘W
- 2 Finger Swipe Left → Page Forward
- 2 Finger Swipe Right → Page Back
- 3 Finger Double-Tap → Activate Currently Hovered App in Dock, затем ⌘H

Два 2-finger горизонтальных trackpad-жеста выполняет нативная macOS настройка **Swipe between pages**. Trickpad 0.14.0 не имеет нужного 2-finger trackpad swipe binding.

## 3. ВАЖНО: TP04 swipe fix принят пользователем и его нельзя откатывать

У стандартного Trickpad обнаружено реальное поведение: один физический 3-finger swipe Up/Down иногда может послать действие повторно и открыть/закрыть **две вкладки**.

TP04 это исправила, и пользователь подтвердил, что этот вариант его устраивает.

Текущая правильная схема в TP08:

```text
3 Finger Swipe Up
→ ~/bin/trickpad-reopen-tab-once
→ ~/bin/trickpad-hide-hovered-dock-app reopen-once
→ ⇧⌘T ровно один раз

3 Finger Swipe Down
→ ~/bin/trickpad-close-tab-once
→ ~/bin/trickpad-hide-hovered-dock-app close-once
→ ⌘W ровно один раз
```

В compiled helper сохранён TP04 quiet-window gate 300 ms. Wrapper-файлы:

```text
~/bin/trickpad-reopen-tab-once
~/bin/trickpad-close-tab-once
```

очень маленькие (~70 B), не являются фоновыми процессами и **не являются мусором**. Их не удалять и не заменять прямыми shortcut bindings.

## 4. Единственная нерешённая проблема

Жест:

```text
Trackpad → 3 Finger Double-Tap
```

должен выполнить:

```text
Activate Currently Hovered App in Dock
→ затем ⌘H
```

Но на реальном Mac каждый вариант helper-а заканчивается одинаковой ошибкой Trickpad:

```text
The “Tap twice with three fingers” script binding didn’t run

“trickpad-hide-hovered-dock-app” stopped
with exit code 2.
```

В TP08 ошибка повторена на реальном Mac. Значит задача **НЕ решена**.

В текущем helper-е exit code 2 означает, что он не смог определить hovered application Dock item.

## 5. Что уже пробовали — НЕ повторять вслепую

### TP03
- `AXUIElementCopyElementAtPosition`
- pointer из `NSEvent.mouseLocation`
- результат на Mac: exit code 2.

### TP04 / TP05
- pointer переведён на `CGEventGetLocation`
- снова `AXUIElementCopyElementAtPosition`
- результат: exit code 2.

### TP06
Полностью отказались от system-wide hit test:
- нашли процесс `com.apple.dock`;
- `AXUIElementCreateApplication(dockPID)`;
- предположили Dock AXList и перебирали `AXDockItem`;
- фильтр `AXApplicationDockItem`;
- сравнение pointer с AX frames;
- nearest-item fallback.
- результат: **exit code 2**.

### TP07
Подход сменён на semantic Dock hover:
- primary: рекурсивно искать `AXSelectedChildren`;
- принимать только `AXApplicationDockItem`;
- secondary fallback: рекурсивно обходить весь Dock AX tree и сравнивать pointer с frame;
- добавлен failure-only diagnostic log.
- результат на реальном Mac: **exit code 2**.

### TP08
Объединено:
- TP04 accepted swipe fix;
- TP07 Dock logic.
- CI зелёный.
- результат на реальном Mac: **тот же exit code 2**.

Поэтому следующий разработчик **не должен делать четвёртую теоретическую переделку без runtime-данных**.

## 6. Самое важное следующее действие

TP07/TP08 специально пишет диагностический файл только при ошибке:

```text
~/Library/Logs/TrickpadPilot/dock-helper.log
```

На момент создания этого handoff содержимое лога ещё не получено из реального Mac.

**Первое действие в новом чате: получить этот лог, прежде чем менять код.**

Дайте пользователю одну read-only команду:

```bash
/bin/cat "$HOME/Library/Logs/TrickpadPilot/dock-helper.log"
```

Если файла нет, затем проверить одним блоком:

```bash
echo "=== helper ==="
/bin/ls -l "$HOME/bin/trickpad-hide-hovered-dock-app"
echo "=== accessibility check ==="
"$HOME/bin/trickpad-hide-hovered-dock-app" --check
echo "status=$?"
echo "=== installed config ==="
/usr/bin/grep -E 'three-finger-(swipe-up|swipe-down|double-tap)' "$HOME/.config/trickpad/config.toml"
echo "=== log ==="
/bin/cat "$HOME/Library/Logs/TrickpadPilot/dock-helper.log" 2>&1
```

После получения лога анализировать **фактическую AX-структуру / selected child / найденные frames / pointer coordinates**, а не предполагать структуру Dock.

## 7. Текущие файлы TP08

Устанавливаются:

```text
~/Applications/Trickpad.app
~/bin/trickpad-hide-hovered-dock-app
~/bin/trickpad-close-tab-once
~/bin/trickpad-reopen-tab-once
~/.config/trickpad/config.toml
```

Accessibility разрешён для:
- Trickpad
- `trickpad-hide-hovered-dock-app`

Wrapper-скриптам отдельное Accessibility-разрешение не нужно: они только `exec`-ят уже разрешённый helper.

## 8. Архитектура TP08 helper

Один compiled Objective-C helper выполняет три режима:

```text
без аргумента    → Dock double-tap action
close-once       → TP04 one-shot ⌘W
reopen-once      → TP04 one-shot ⇧⌘T
--check          → проверка Accessibility
```

Это намеренно один бинарник, чтобы не плодить резидентные процессы. Wrapper-ы — обычные короткие shell-файлы.

## 9. CI / артефакт TP08

GitHub Actions run: `36282682117` — success.

Artifact:
`Trickpad-Pilot-0.14.0-TP08`

Artifact ID:
`10919332446`

Outer artifact SHA-256:
`ef5a6cd4d051b63e6d4becb3b484041d52ba58e6a705642b851666610f6b27e2`

Ready-to-install inner ZIP SHA-256:
`7c2951b583512cb0fb152fe05ccd8e8bbf2233b54f0e86b2c1ae845e094cfe7e`

CI проверяет:
- upstream Trickpad 0.14.0 без изменений;
- arm64 helper;
- codesign;
- наличие обоих TP04 wrappers;
- wrapper bindings для mouse + trackpad swipe up/down;
- double-tap binding на Dock helper.

## 10. Ограничения проекта

- Не устанавливать Homebrew.
- Не требовать Xcode / Command Line Tools на пользовательском Mac.
- CLI/helper файлы держать в `~/bin`.
- Не добавлять новые постоянно работающие процессы без необходимости.
- Не ломать TP04 swipe behavior.
- Не начинать работу заново: источник истины — ветка `trickpad-pilot` + `agents.md` + этот handoff.
- Каждый функциональный commit дописывать отдельным подразделом в `agents.md`.

## 11. Рекомендуемая стратегия для следующей модели

1. Прочитать `agents.md`, особенно TP01–TP08.1.
2. Не менять swipe code.
3. Получить `dock-helper.log` с реального Mac.
4. По логу определить, на каком этапе TP07 Dock resolution ломается:
   - нет Dock process;
   - AX tree недоступен;
   - `AXSelectedChildren` пуст;
   - subrole отличается;
   - recursive traversal не видит items;
   - frames в другом coordinate space;
   - gesture срабатывает после ухода pointer/смены hover state;
   - другая фактическая причина.
5. Только затем делать следующий минимальный commit.
6. Если проблема оказывается таймингом между gesture recognition и Dock hover state, сначала доказать это логом; не добавлять произвольные delay/polling loops вслепую.
7. После фикса собрать через GitHub Actions и дать готовый arm64 ZIP.

## 12. Текущий статус

**TP08 является базой, но Dock double-tap не работает.**

Свайп-часть TP04 сохранять.  
Dock-часть требует диагностики по реальному `dock-helper.log`.

Это точка продолжения работы.
