const getBaseUrl = () => {
  if (typeof GetParentResourceName !== "undefined") {
    return `https://${GetParentResourceName()}/`;
  }

  return "https://bcc-chat/";
};

export async function nuiPost(endpoint, payload = {}) {
  try {
    const response = await fetch(`${getBaseUrl()}${endpoint}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json; charset=UTF-8",
      },
      body: JSON.stringify(payload),
    });

    return await response.text();
  } catch (error) {
    console.error(`[bcc-chat] nuiPost(${endpoint}) failed`, error);
    return null;
  }
}
