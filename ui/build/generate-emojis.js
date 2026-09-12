const fs = require("fs");
const path = require("path");

const sourcePath = process.argv[2];
const projectRoot = path.resolve(__dirname, "..");
const outputPath = path.join(projectRoot, "src", "emoji-data.mjs");

if (!sourcePath) {
  throw new Error("Usage: node build/generate-emojis.js <emoji-test.txt>");
}

const groupDetails = {
  "Smileys & Emotion": { labelKey: "emojiFaces", icon: "😀" },
  "People & Body": { labelKey: "emojiPeople", icon: "👋" },
  Component: { labelKey: "emojiComponents", icon: "🦰" },
  "Animals & Nature": { labelKey: "emojiAnimals", icon: "🐺" },
  "Food & Drink": { labelKey: "emojiFood", icon: "🍻" },
  "Travel & Places": { labelKey: "emojiTravel", icon: "🚂" },
  Activities: { labelKey: "emojiActivities", icon: "🎯" },
  Objects: { labelKey: "emojiObjects", icon: "💡" },
  Symbols: { labelKey: "emojiSymbols", icon: "❤️" },
  Flags: { labelKey: "emojiFlags", icon: "🏳️" },
};

const westernEmoji = [
  "🤠", "🐎", "🐴", "🦬", "🐂", "🐄", "🐐", "🦌", "🐺", "🦅", "🐍", "🌵",
  "🏜️", "🏕️", "⛺", "🪶", "🪵", "🪨", "🔥", "🚂", "🛤️", "🛶", "🛞", "🎯",
  "🔫", "🗡️", "🪓", "⛏️", "🧨", "🪤", "🔒", "🔑", "⚖️", "⭐", "💰", "💵",
  "🪙", "💎", "🍻", "🍺", "🥃", "🍾", "🚬", "🎲", "🃏", "♠️", "♥️", "♦️", "♣️",
  "🎵", "🎻", "🪕", "📜", "✉️", "🕯️", "⌛", "🧭", "🗺️", "☀️", "🌙", "⛈️",
];

const names = new Map();
const groups = new Map();
let currentGroup = "";

for (const line of fs.readFileSync(sourcePath, "utf8").split(/\r?\n/)) {
  const groupMatch = line.match(/^# group: (.+)$/);
  if (groupMatch) {
    currentGroup = groupMatch[1];
    continue;
  }

  const entryMatch = line.match(/^([0-9A-F ]+)\s+;\s+(fully-qualified|component)\s+#\s+(\S+)\s+E[0-9.]+\s+(.+)$/);
  if (!entryMatch || !groupDetails[currentGroup]) {
    continue;
  }

  const emoji = entryMatch[3];
  names.set(emoji, entryMatch[4]);
  if (!groups.has(currentGroup)) {
    groups.set(currentGroup, []);
  }
  groups.get(currentGroup).push(emoji);
}

const outputGroups = [
  {
    labelKey: "emojiWestern",
    icon: "🤠",
    items: westernEmoji,
  },
  ...Object.entries(groupDetails).map(([groupName, details]) => ({
    ...details,
    items: groups.get(groupName) || [],
  })),
];

const searchableNames = Object.fromEntries(
  outputGroups.flatMap((group) => group.items).map((emoji) => [emoji, names.get(emoji) || "western"])
);

const output = [
  "// Generated from Unicode Emoji 17.0 emoji-test.txt. Do not edit by hand.",
  `export const emojiGroups = ${JSON.stringify(outputGroups, null, 2)};`,
  `export const emojiNames = ${JSON.stringify(searchableNames, null, 2)};`,
  "",
].join("\n");

fs.writeFileSync(outputPath, output, "utf8");

const uniqueEmoji = new Set(outputGroups.flatMap((group) => group.items));
console.info(`Generated ${uniqueEmoji.size} unique emoji across ${outputGroups.length} groups.`);
