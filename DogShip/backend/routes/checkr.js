const express = require('express');
const router = express.Router();
const axios = require('axios');

router.post('/create-candidate', async (req, res) => {
  try {
    const { firstName, lastName, email } = req.body;
    const response = await axios.post('https://api.checkr.com/v1/candidates', {
      given_name: firstName, family_name: lastName, email
    }, { auth: { username: process.env.CHECKR_API_KEY, password: '' } });
    res.json(response.data);
  } catch (e) {
    console.error(e.response?.data || e.message);
    res.status(500).json({ error: e.message });
  }
});
module.exports = router;
