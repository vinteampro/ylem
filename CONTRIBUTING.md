# Contributing to Ylem / Как помочь проекту

[English](#english) · [Русский](#русский)

---

## English

Ylem is a small game built on a real model of the early Universe. Two kinds of help are
welcome: making the physics more accurate and making the game richer. Issues and pull
requests in English or Russian are both fine.

### Getting started

1. Install [Godot 4.7](https://godotengine.org/download/) (standard build, GDScript only).
2. Open `project.godot` and press **F5**.
3. Run the physics check (about 30 seconds, no graphics):

   ```
   godot --headless --path . --script res://tools/sim_check.gd
   ```

   It must end with `ИТОГ: всё в допусках` ("all within tolerance").

Useful debug arguments (start temperature, levers, screenshots) are listed in the README,
section "For development".

### Where things live

- `scripts/universe.gd` — the physics model: numbers only, no graphics.
- `tools/sim_check.gd` — the check against AlterBBN 2.2 and Planck 2018.
- `scripts/main.gd`, `scripts/hud.gd`, `scripts/particle_field.gd` — game, interface, particles.
- `scripts/audio_director.gd` — sound; `scripts/i18n.gd` — every text in both languages.

### Rules for physics changes

The game promises "a meditation built on real physics". To keep that promise:

- **No fudge factors.** Every constant and rate comes from a published source. Put the
  reference in a comment next to the number (author, year, journal or arXiv id).
- **`sim_check.gd` must pass.** If your change improves agreement, tighten the tolerance in
  the same pull request.
- **Say what changed in numbers.** In the pull request, paste the `sim_check` output before
  and after.
- **Update the README.** If you remove a simplification, take it off the "Simplified" list;
  if you add one, put it there.
- Keep the in-game forecast fast: it runs with a coarse step (0.05), and `sim_check` verifies
  it stays close to the fine step.

### Gameplay, sound and texts

- New text goes into `scripts/i18n.gd` in both Russian and English. If you only speak one of
  them, write it and say so in the pull request.
- A new lever or visual effect should not contradict the model. If it is artistic licence
  (like the player's hand), say so in the "Simplified" list.
- Keep the mood: no fail states, no timers, nothing that shouts.

### Pull requests

- One topic per pull request.
- Describe what you changed and how you checked it; screenshots or a short GIF for visual
  changes.
- For anything large, open an issue first so we can agree on the approach.

### Licence

Code contributions are accepted under the [MIT licence](LICENSE). The music, splash screen and
icon are not open (see [ASSETS_LICENSE.md](ASSETS_LICENSE.md)); please don't modify them or
submit replacements without discussing it first.

---

## Русский

Ylem — небольшая игра на настоящей модели ранней Вселенной. Помощь нужна в двух
направлениях: сделать физику точнее и игру богаче. Issues и pull requests можно писать
по-русски или по-английски.

### С чего начать

1. Установи [Godot 4.7](https://godotengine.org/download/) (обычная сборка, только GDScript).
2. Открой `project.godot` и нажми **F5**.
3. Запусти проверку физики (около 30 секунд, без графики):

   ```
   godot --headless --path . --script res://tools/sim_check.gd
   ```

   В конце должно быть `ИТОГ: всё в допусках`.

Отладочные аргументы (стартовая температура, рычаги, скриншоты) — в README, раздел
«Для разработки».

### Что где лежит

- `scripts/universe.gd` — физическая модель: только числа, без графики.
- `tools/sim_check.gd` — проверка против AlterBBN 2.2 и Planck 2018.
- `scripts/main.gd`, `scripts/hud.gd`, `scripts/particle_field.gd` — игра, интерфейс, частицы.
- `scripts/audio_director.gd` — звук; `scripts/i18n.gd` — все тексты на двух языках.

### Правила для изменений в физике

Игра обещает «медитацию на научной основе». Чтобы это обещание держалось:

- **Никаких подгоночных коэффициентов.** Каждая константа и скорость реакции берётся из
  опубликованного источника. Ссылку пиши в комментарии рядом с числом (автор, год, журнал
  или arXiv).
- **`sim_check.gd` должен проходить.** Если изменение улучшает согласие, сузь допуск в том
  же pull request.
- **Покажи изменения в числах.** В pull request приложи вывод `sim_check` до и после.
- **Обнови README.** Убрал упрощение — вычеркни его из списка «Упрощено»; добавил — впиши.
- Прогноз в игре должен оставаться быстрым: он считается крупным шагом (0,05), и
  `sim_check` проверяет, что он близок к точному счёту.

### Геймплей, звук и тексты

- Новые тексты — в `scripts/i18n.gd`, сразу на русском и английском. Если знаешь только
  один язык, напиши на нём и предупреди в pull request.
- Новый рычаг или эффект не должен противоречить модели. Если это художественная вольность
  (как рука игрока), так и напиши в списке «Упрощено».
- Сохраняем настроение: без проигрышей, таймеров и всего, что кричит.

### Pull requests

- Одна тема — один pull request.
- Опиши, что изменил и как проверил; для визуальных изменений — скриншот или короткая гифка.
- Для крупных изменений сначала открой issue, чтобы договориться о подходе.

### Лицензия

Код принимается под [лицензией MIT](LICENSE). Музыка, заставка и иконка закрыты (см.
[ASSETS_LICENSE.md](ASSETS_LICENSE.md)): не меняй их и не присылай замену без обсуждения.
