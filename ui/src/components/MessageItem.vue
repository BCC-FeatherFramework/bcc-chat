<script setup>
import { computed } from "vue";

const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
  activeMode: {
    type: Object,
    required: true,
  },
  templates: {
    type: Object,
    required: true,
  },
  localeCode: {
    type: String,
    default: "en-GB",
  },
});

const defaultTemplateId = "default";
const defaultAltTemplateId = "defaultAlt";

const renderedLine = computed(() => {
  let template = props.message.template || props.templates[props.message.templateId || defaultTemplateId];
  const templateId = props.message.templateId || defaultTemplateId;
  const args = props.message.args || [];
  const params = props.message.params || {};

  if (!props.message.template && templateId === defaultTemplateId && args.length === 1) {
    template = props.templates[defaultAltTemplateId];
  }

  if (!template) {
    template = args.length > 1 ? "<b>{0}</b>: {1}" : "{0}";
  }

  template = template.replace("@default", props.templates[templateId] || "");

  let output = template.replace(/{(\d+)}/g, (match, number) => {
    const value = args[number] !== undefined ? escapeHtml(args[number]) : match;
    if (Number(number) === 0 && props.message.color) {
      return colorizeOld(value);
    }
    return value;
  });

  output = output.replace(/\{\{([a-zA-Z0-9_-]+?)\}\}/g, (match, id) => {
    return params[id] !== undefined ? escapeHtml(params[id]) : match;
  });

  return colorize(output);
});

const timestampLabel = computed(() => {
  if (!props.message.createdAtMs) {
    return "";
  }

  return new Intl.DateTimeFormat(props.localeCode || "en-GB", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(props.message.createdAtMs));
});

const timestampTitle = computed(() => {
  if (!props.message.createdAtMs) {
    return "";
  }

  return new Intl.DateTimeFormat(props.localeCode || "en-GB", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).format(new Date(props.message.createdAtMs));
});

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function colorizeOld(value) {
  const color = props.message.color || [255, 255, 255];
  return `<span style="color: rgb(${color[0]}, ${color[1]}, ${color[2]})">${value}</span>`;
}

function colorize(value) {
  let output = `<span>${colorTrans(value)}</span>`;

  const styleDict = {
    "*": "font-weight: bold;",
    _: "text-decoration: underline;",
    "~": "text-decoration: line-through;",
    "=": "text-decoration: underline line-through;",
    r: "text-decoration: none;font-weight: normal;",
  };

  const styleRegex = /\^(_|\*|=|~|\/|r)(.*?)(?=$|\^r|<\/em>)/;

  while (output.match(styleRegex)) {
    output = output.replace(styleRegex, (full, style, inner) => {
      return `<em style="${styleDict[style] || ""}">${inner}</em>`;
    });
  }

  return output.replace(/<span[^>]*><\/span[^>]*>/g, "");
}

function colorTrans(value) {
  return value
    .replace(/\^([0-9])/g, (full, color) => `</span><span class="color-${color}">`)
    .replace(/\^#([0-9A-F]{3,6})/gi, (full, color) => `</span><span class="color" style="color: #${color}">`)
    .replace(/~([a-z])~/g, (full, color) => `</span><span class="gameColor-${color}">`);
}
</script>

<template>
  <div class="msg" :class="{ multiline: message.multiline }">
    <div class="msg-row">
      <span class="msg-line" v-html="renderedLine"></span>
      <span v-if="timestampLabel" class="msg-time" :title="timestampTitle">{{ timestampLabel }}</span>
    </div>
  </div>
</template>

<style scoped>
.msg-row {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 0.8rem;
}

.msg-line {
  min-width: 0;
  flex: 1 1 auto;
}

.msg-time {
  flex: 0 0 auto;
  margin-top: 0.08rem;
  color: rgba(255, 255, 255, 0.58);
  font-size: 0.72em;
  font-weight: 600;
  white-space: nowrap;
  text-align: right;
}
</style>
