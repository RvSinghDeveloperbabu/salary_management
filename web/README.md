# Frontend

React 19 + TypeScript, built with Vite. This file explains **every library
used beyond plain React**, why it is here, and the small slice of each one
this project actually touches.

If you know components, props, hooks and `fetch`, that is enough to follow
everything below. Each library is introduced by the problem it solves, so
you can decide for yourself whether it earned its place.

---

## The short version

| Library | What it replaces | How much of it we use |
| --- | --- | --- |
| React Router | Manual "which screen is showing" state | 4 things: `Routes`, `Route`, `Link`, `useParams` |
| TanStack Query | `useEffect` + `useState` + loading/error flags | Mostly one hook: `useQuery` |
| Mantine | Hand-written CSS for buttons, inputs, layout | Components only — `<Button>`, `<Table>`, `<Select>` |
| TanStack Table | Manual sort/paginate logic in the table component | One hook: `useReactTable` |
| Recharts | Drawing SVG charts by hand | `<LineChart>`, `<BarChart>` and their parts |
| Vitest + RTL | — (this is the test runner) | `render`, `screen`, `expect` |
| MSW | Stubbing `fetch` in tests | `http.get(...)` handlers |

---

## 1. React Router — URLs for screens

**Problem it solves.** Without it you need state like
`const [screen, setScreen] = useState("dashboard")`. That works, but every
screen shares one URL: the back button does nothing, and you cannot send
someone a link to one employee.

**What we use:**

```tsx
<Routes>
  <Route path="/" element={<Dashboard />} />
  <Route path="/employees" element={<Directory />} />
  <Route path="/employees/:id" element={<EmployeeDetail />} />
</Routes>
```

- `<Link to="/employees">` — like `<a href>`, but does not reload the page.
- `useParams()` — reads `:id` out of the URL: `const { id } = useParams()`.
- `useNavigate()` — go somewhere in response to an event, e.g. after login.

That is the whole surface area used here.

---

## 2. TanStack Query — fetching without the boilerplate

**Problem it solves.** The plain version of loading data is this, repeated
in every component:

```tsx
const [data, setData] = useState(null);
const [loading, setLoading] = useState(true);
const [error, setError] = useState(null);

useEffect(() => {
  fetch("/api/v1/employees")
    .then((r) => r.json())
    .then(setData)
    .catch(setError)
    .finally(() => setLoading(false));
}, []);
```

Four pieces of state and an effect, every time. It also refetches from
scratch on every mount, has no caching, and handling "the filter changed,
cancel the in-flight request" correctly is fiddly.

**What we use instead:**

```tsx
const { data, isLoading, error } = useQuery({
  queryKey: ["employees", filters],
  queryFn: () => apiGet("/employees", filters),
});
```

- `queryKey` is a cache key. Change the filters and it refetches
  automatically; go back to the previous filters and it serves the cached
  answer instantly.
- `queryFn` is **just a function that returns a promise** — ours still uses
  plain `fetch` underneath. Nothing is hidden.
- `useMutation` is the same idea for writes (recording a salary change),
  plus `invalidateQueries` to tell the cache "this data is stale now".

**The mental model:** `useQuery` is `useEffect` + `useState` + caching,
wrapped up. The `fetch` call is still yours.

---

## 3. Mantine — prebuilt UI components

**Problem it solves.** Writing accessible buttons, dropdowns, modals and a
responsive layout in raw CSS is a lot of work that has nothing to do with
this application.

**What we use.** Only components, passed props, exactly like your own:

```tsx
<Button onClick={save} loading={isSaving}>Save</Button>
<Select label="Department" data={options} value={value} onChange={setValue} />
<Table><Table.Tr><Table.Td>…</Table.Td></Table.Tr></Table>
```

No special concepts. `<MantineProvider>` wraps the app once in `main.tsx`
to supply the theme; everything after that is ordinary components.

---

## 4. TanStack Table — table logic, not table markup

**Problem it solves.** Column definitions, sort state and pagination state
otherwise get hand-written into the component and tangled with the markup.

**Important:** it renders nothing. It is a hook that hands you rows and
headers; we still write the `<table>` markup ourselves.

```tsx
const table = useReactTable({ data, columns, getCoreRowModel: getCoreRowModel() });

table.getRowModel().rows.map((row) => /* your own <tr> */);
```

Sorting and pagination here are **server-side** — the Rails API does the
work, and the table just reports which column was clicked.

---

## 5. Recharts — charts as components

**Problem it solves.** Axes, scales, tooltips and responsive resizing in
hand-written SVG is genuinely hard.

**What we use.** It looks like ordinary JSX with props:

```tsx
<ResponsiveContainer width="100%" height={300}>
  <LineChart data={points}>
    <XAxis dataKey="month" />
    <YAxis />
    <Tooltip />
    <Line dataKey="total" />
  </LineChart>
</ResponsiveContainer>
```

`data` is a plain array of objects; `dataKey` names which field to plot.

---

## 6. Vitest, React Testing Library and MSW — the tests

- **Vitest** runs the tests. The API is Jest's: `describe`, `it`, `expect`.
- **React Testing Library** renders a component and queries it the way a
  user would: `screen.getByRole("button", { name: "Save" })`.
- **MSW** intercepts `fetch` during tests and returns fixed JSON, so tests
  never touch the real API and never depend on the database.

```ts
http.get("/api/v1/employees", () => HttpResponse.json({ employees: [...] }));
```

The component under test still calls `fetch` normally — MSW answers it.

---

## Running it

Everything runs in Docker. Nothing is installed on your machine.

```sh
docker compose up                              # app on http://localhost:5173
docker compose run --rm web npm test           # tests
docker compose run --rm web npm run typecheck  # TypeScript
docker compose run --rm web npm run build      # bundle into ../api/public
```

In development Vite serves the app on `:5173` and forwards anything starting
with `/api` to Rails on `:3000`. That forwarding happens on the server side,
so the browser only ever talks to one origin — which is why there is no CORS
configuration anywhere in this project.
