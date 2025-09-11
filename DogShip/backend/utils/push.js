const fetch = require('node-fetch');
async function sendExpoPushAsync(messages) {
  const chunks = [];
  const CHUNK_SIZE = 90;
  for (let i = 0; i < messages.length; i += CHUNK_SIZE) chunks.push(messages.slice(i, i + CHUNK_SIZE));
  const tickets = [];
  for (const chunk of chunks) {
    const res = await fetch('https://exp.host/--/api/v2/push/send', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(chunk)
    });
    tickets.push(await res.json());
  }
  return tickets;
}
module.exports = { sendExpoPushAsync };
