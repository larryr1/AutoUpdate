const express = require("express");
const app = express();

app.get("/v1/update_configuration", (req, res) => {
  console.log("Got request for config.");

  res.json({
    logon: {
      completion: {
        username: "bluebooks@testing",
        password: "student"
      },
      continuity: {
        username: "au",
        password: "student"
      }
    }
  })
})

console.log("Listening on 8000.");
app.listen(8000);