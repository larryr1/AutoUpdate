const express = require("express");
const app = express();

const config = require("./config.json");

app.get("/v1/update_configuration", (req, res) => {
  console.log("Got request for config.");

  res.json(config);
})

console.log("Listening on 8000.");
app.listen(8000);