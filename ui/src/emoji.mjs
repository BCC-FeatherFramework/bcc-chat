import { emojiGroups, emojiNames } from "./emoji-data.mjs";

export { emojiGroups };

export function searchEmoji(items, query) {
  const search = String(query || "").trim().toLocaleLowerCase();
  if (!search) {
    return items;
  }

  return items.filter((emoji) =>
    (emojiNames[emoji] || "").toLocaleLowerCase().includes(search)
  );
}
