const getBaseUrl = () => {
  if (typeof GetParentResourceName !== "undefined") {
    return `https://${GetParentResourceName()}/`;
  }

  return "https://bcc-chat/";
};

export async function nuiPost(endpoint, payload = {}) {
  const response = await fetch(`${getBaseUrl()}${endpoint}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=UTF-8",
    },
    body: JSON.stringify(payload),
  });

  return response.text();
}
