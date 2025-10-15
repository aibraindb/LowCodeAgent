import express from "express";
import multer from "multer";
import axios from "axios";
const app = express();
const upload = multer({ dest: "/data/uploads" });
app.use(express.json());

const SPRING_BASE = process.env.SPRING_BASE || "http://server:8080";

// health
app.get("/health", (_, res) => res.json({ status:"UP", service:"nodeapi" }));

// upload document (excel/word/pdf/ppt/html) — just stores and echoes path
app.post("/upload", upload.single("file"), async (req, res) => {
  const { originalname, path } = req.file || {};
  res.json({ ok:true, name: originalname, path });
});

// build prompt (configurable)
app.post("/prompt/assemble", async (req, res) => {
  try {
    const { data } = await axios.post(`${SPRING_BASE}/api/assemble`, req.body, { timeout: 60000 });
    res.json(data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.listen(4000, () => console.log("Node API listening on 4000"));
