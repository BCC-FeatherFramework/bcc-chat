<script setup>
import { computed } from "vue";

const props = defineProps({
  message: {
    type: String,
    required: true,
  },
  suggestions: {
    type: Array,
    required: true,
  },
});

const currentSuggestions = computed(() => {
  if (props.message === "") {
    return [];
  }

  const suggestions = props.suggestions
    .filter((suggestion) => {
      if (suggestion.name.startsWith(props.message)) {
        return true;
      }

      const suggestionParts = suggestion.name.split(" ");
      const messageParts = props.message.split(" ");

      for (let i = 0; i < messageParts.length; i += 1) {
        if (i >= suggestionParts.length) {
          return i < suggestionParts.length + (suggestion.params || []).length;
        }

        if (suggestionParts[i] !== messageParts[i]) {
          return false;
        }
      }

      return true;
    })
    .slice(0, 5)
    .map((suggestion) => {
      const cloned = {
        ...suggestion,
        params: (suggestion.params || []).map((param) =>
          typeof param === "string" ? { name: param, help: "", disabled: false } : { ...param, disabled: false }
        ),
      };

      cloned.disabled = !cloned.name.startsWith(props.message);

      cloned.params.forEach((param, index) => {
        const wordType = index === cloned.params.length - 1 ? "." : "\\S";
        const regex = new RegExp(`${cloned.name} (?:\\w+ ){${index}}(?:${wordType}*)$`, "g");
        param.disabled = props.message.match(regex) == null;
      });

      return cloned;
    });

  return suggestions;
});
</script>

<template>
  <div class="suggestions-wrap" v-show="currentSuggestions.length > 0">
    <ul class="suggestions">
      <li v-for="suggestion in currentSuggestions" :key="suggestion.name" class="suggestion">
        <p>
          <span :class="{ disabled: suggestion.disabled }">{{ suggestion.name }}</span>
          <span
            v-for="param in suggestion.params"
            :key="param.name"
            class="param"
            :class="{ disabled: param.disabled }"
          >
            [{{ param.name }}]
          </span>
        </p>
        <small class="help">
          <template v-if="!suggestion.disabled">{{ suggestion.help }}</template>
          <template v-for="param in suggestion.params" :key="`${suggestion.name}-${param.name}`">
            <template v-if="!param.disabled">{{ param.help }}</template>
          </template>
        </small>
      </li>
    </ul>
  </div>
</template>
