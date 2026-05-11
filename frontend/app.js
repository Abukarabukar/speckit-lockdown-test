const API = 'http://localhost:3001/api';

const $ = (id) => document.getElementById(id);
const authView = $('auth-view');
const appView = $('app-view');
const authForm = $('auth-form');
const authTitle = $('auth-title');
const authSubmit = $('auth-submit');
const authToggle = $('auth-toggle');
const authToggleText = $('auth-toggle-text');
const authError = $('auth-error');
const todoForm = $('todo-form');
const todoText = $('todo-text');
const todoList = $('todos');
const todoError = $('todo-error');
const meEl = $('me');
const logoutBtn = $('logout');

let mode = 'login';
let token = localStorage.getItem('token');
let username = localStorage.getItem('username');

function showError(el, msg) {
  el.textContent = msg;
  el.hidden = !msg;
}

function setView() {
  if (token && username) {
    authView.hidden = true;
    appView.hidden = false;
    meEl.textContent = username;
    loadTodos();
  } else {
    authView.hidden = false;
    appView.hidden = true;
  }
}

async function api(path, opts = {}) {
  const res = await fetch(API + path, {
    ...opts,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: 'Bearer ' + token } : {}),
      ...(opts.headers || {}),
    },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || 'Request failed');
  return data;
}

authToggle.addEventListener('click', (e) => {
  e.preventDefault();
  mode = mode === 'login' ? 'register' : 'login';
  authTitle.textContent = mode === 'login' ? 'Sign in' : 'Create account';
  authSubmit.textContent = mode === 'login' ? 'Sign in' : 'Create account';
  authToggleText.textContent = mode === 'login' ? 'No account?' : 'Already have one?';
  authToggle.textContent = mode === 'login' ? 'Create one' : 'Sign in';
  showError(authError, '');
});

authForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  showError(authError, '');
  try {
    const data = await api('/' + mode, {
      method: 'POST',
      body: JSON.stringify({ username: $('username').value, password: $('password').value }),
    });
    token = data.token;
    username = data.username;
    localStorage.setItem('token', token);
    localStorage.setItem('username', username);
    authForm.reset();
    setView();
  } catch (err) {
    showError(authError, err.message);
  }
});

logoutBtn.addEventListener('click', () => {
  token = null;
  username = null;
  localStorage.removeItem('token');
  localStorage.removeItem('username');
  setView();
});

async function loadTodos() {
  showError(todoError, '');
  try {
    const todos = await api('/todos');
    renderTodos(todos);
  } catch (err) {
    if (err.message === 'invalid token' || err.message === 'missing token') {
      logoutBtn.click();
      return;
    }
    showError(todoError, err.message);
  }
}

function renderTodos(todos) {
  todoList.innerHTML = '';
  for (const t of todos) {
    const li = document.createElement('li');
    if (t.done) li.classList.add('done');

    const cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.checked = t.done;
    cb.addEventListener('change', () => toggle(t.id, cb.checked));

    const span = document.createElement('span');
    span.className = 'text';
    span.textContent = t.text;

    const del = document.createElement('button');
    del.className = 'delete';
    del.title = 'Delete';
    del.textContent = '×';
    del.addEventListener('click', () => remove(t.id));

    li.append(cb, span, del);
    todoList.appendChild(li);
  }
}

todoForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const text = todoText.value.trim();
  if (!text) return;
  try {
    await api('/todos', { method: 'POST', body: JSON.stringify({ text }) });
    todoText.value = '';
    loadTodos();
  } catch (err) {
    showError(todoError, err.message);
  }
});

async function toggle(id, done) {
  try {
    await api('/todos/' + id, { method: 'PATCH', body: JSON.stringify({ done }) });
    loadTodos();
  } catch (err) {
    showError(todoError, err.message);
  }
}

async function remove(id) {
  try {
    await api('/todos/' + id, { method: 'DELETE' });
    loadTodos();
  } catch (err) {
    showError(todoError, err.message);
  }
}

setView();
