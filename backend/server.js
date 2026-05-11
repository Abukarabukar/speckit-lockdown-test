import express from 'express';
import cors from 'cors';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_FILE = path.join(__dirname, 'data.json');
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-me';
const PORT = process.env.PORT || 3001;

async function loadData() {
  try {
    const raw = await fs.readFile(DATA_FILE, 'utf8');
    return JSON.parse(raw);
  } catch (err) {
    if (err.code === 'ENOENT') return { users: [], todos: [] };
    throw err;
  }
}

async function saveData(data) {
  await fs.writeFile(DATA_FILE, JSON.stringify(data, null, 2));
}

const app = express();
app.use(cors());
app.use(express.json());

function auth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'missing token' });
  try {
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch {
    res.status(401).json({ error: 'invalid token' });
  }
}

app.post('/api/register', async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ error: 'username and password required' });
  const data = await loadData();
  if (data.users.some((u) => u.username === username)) {
    return res.status(409).json({ error: 'username already taken' });
  }
  const id = (data.users.at(-1)?.id ?? 0) + 1;
  const passwordHash = await bcrypt.hash(password, 10);
  data.users.push({ id, username, passwordHash });
  await saveData(data);
  const token = jwt.sign({ id, username }, JWT_SECRET, { expiresIn: '7d' });
  res.json({ token, username });
});

app.post('/api/login', async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ error: 'username and password required' });
  const data = await loadData();
  const user = data.users.find((u) => u.username === username);
  if (!user) return res.status(401).json({ error: 'invalid credentials' });
  const ok = await bcrypt.compare(password, user.passwordHash);
  if (!ok) return res.status(401).json({ error: 'invalid credentials' });
  const token = jwt.sign({ id: user.id, username: user.username }, JWT_SECRET, { expiresIn: '7d' });
  res.json({ token, username: user.username });
});

app.get('/api/todos', auth, async (req, res) => {
  const data = await loadData();
  const todos = data.todos.filter((t) => t.userId === req.user.id);
  res.json(todos);
});

app.post('/api/todos', auth, async (req, res) => {
  const { text } = req.body || {};
  if (!text || typeof text !== 'string') return res.status(400).json({ error: 'text required' });
  const data = await loadData();
  const id = (data.todos.at(-1)?.id ?? 0) + 1;
  const todo = { id, userId: req.user.id, text: text.trim(), done: false, createdAt: Date.now() };
  data.todos.push(todo);
  await saveData(data);
  res.json(todo);
});

app.patch('/api/todos/:id', auth, async (req, res) => {
  const id = Number(req.params.id);
  const data = await loadData();
  const todo = data.todos.find((t) => t.id === id && t.userId === req.user.id);
  if (!todo) return res.status(404).json({ error: 'not found' });
  if (typeof req.body.done === 'boolean') todo.done = req.body.done;
  if (typeof req.body.text === 'string') todo.text = req.body.text.trim();
  await saveData(data);
  res.json(todo);
});

app.delete('/api/todos/:id', auth, async (req, res) => {
  const id = Number(req.params.id);
  const data = await loadData();
  const before = data.todos.length;
  data.todos = data.todos.filter((t) => !(t.id === id && t.userId === req.user.id));
  if (data.todos.length === before) return res.status(404).json({ error: 'not found' });
  await saveData(data);
  res.json({ ok: true });
});

app.listen(PORT, () => {
  console.log(`Backend listening on http://localhost:${PORT}`);
});
