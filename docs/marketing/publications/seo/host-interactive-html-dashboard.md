---
title: "Host an Interactive HTML Dashboard | FastShared"
description: "Host and share interactive HTML dashboards (Plotly, Evidence, Streamlit static exports) with clients. Step-by-step methods and instant links."
---

# How to host an interactive HTML dashboard for clients

Data consultants, financial analysts, and BI specialists are increasingly moving away from static PDF decks. Modern data libraries allow you to compile rich, interactive dashboards directly into standalone HTML files that run entirely in the browser.

Whether you generate charts using Python (Plotly, Bokeh), R (Quarto, Shiny static exports), or modern markdown-driven BI tools (Evidence.dev, Observable Framework), you get self-contained web applications with interactive tooltips, responsive zoom, and instant filtering.

However, delivering that HTML dashboard to an executive client presents a dilemma. You need a fast, professional way to host it without running an expensive cloud server or forcing your client to create an account.

Here is how to host and share interactive HTML dashboards cleanly.

---

## The problem with traditional dashboard hosting

When sharing a static data dashboard with an external stakeholder, traditional options often introduce significant friction:

1. **Enterprise BI platforms (Tableau, PowerBI):** Require per-user licensing fees, corporate SSO integration, and client onboarding. For a solo consultant delivering a one-time audit, this is prohibitive.
2. **Dedicated cloud servers (AWS EC2, Render, Heroku):** Running a live backend server for a dashboard that only serves static data creates unnecessary hosting bills and ongoing maintenance.
3. **Emailing `.html` files:** When recipients save and open HTML dashboards locally from disk (`file://`), modern browser security settings frequently disable embedded JavaScript engines and local data fetch requests. The charts fail to render.

---

## Method 1: Host via GitHub Pages (Free, public projects)

If your dashboard does not contain confidential client information, GitHub Pages is a reliable free hosting platform.

### Step-by-step with Python Plotly:
1. Export your Plotly dashboard as a standalone HTML file:
   ```python
   import plotly.express as px

   df = px.data.iris()
   fig = px.scatter(df, x="sepal_width", y="sepal_length", color="species")
   fig.write_html("index.html", include_plotlyjs="cdn")
   ```
2. Create a new public repository on GitHub named `client-dashboard`.
3. Push your `index.html` file to the `main` branch.
4. Navigate to **Settings** > **Pages** in your repository.
5. Under **Branch**, select `main` and root `/`, then click **Save**.
6. GitHub will deploy your dashboard to `https://<username>.github.io/client-dashboard/`.

### When this method falls short:
- **Confidentiality:** Free GitHub Pages requires a public repository. If your dashboard contains proprietary business metrics, public hosting is a non-starter.
- **Zero open alerts:** You have no way of knowing when your client views the dashboard.
- **Maintenance burden:** Over time, your GitHub account becomes cluttered with abandoned repositories for past client projects.

---

## Method 2: Instant hosting with FastShared (Private, notified)

FastShared gives consultants the fastest way to host client dashboards as clean web links with real-time open notifications.

### Step-by-step:
1. **Export your dashboard:** Save your dashboard as a single HTML file or compress your compiled project folder (containing `index.html` and assets) into a `.zip` file.
2. **Drop and publish:** Drag the file directly onto [fastsha.red](https://fastsha.red) or push it from your terminal:
   ```bash
   fastshared publish ./dashboard.html
   ```
3. **Send the clean link:** Copy the short URL and paste it into your client email or Slack thread.
4. **Get notified on your phone:** As soon as your client loads the dashboard in their browser, your iPhone receives a push alert: *Opened in a browser*.

### Why consultants prefer this approach:
- **Isolated sandbox:** Deliverables run on a dedicated, isolated subdomain, ensuring client scripts execute safely without accessing main-domain cookies.
- **Real-time notifications:** Know the moment your dashboard is opened in a real browser so you can time your follow-up conversation.
- **No client friction:** The client clicks the link and views the dashboard in full screen on desktop or tablet. No logins, passwords, or viewer software required.
- **Automatic lifecycle:** Free publications expire cleanly after seven days. Pro publications stay online as long as your membership is active, with 30-day cancellation protection.

---

## Checklist for sharing client dashboards

- **Pre-aggregate sensitive data:** Never bundle raw database credentials or unmasked PII into the client-side JavaScript bundle. Summarize metrics before exporting to HTML.
- **Optimize bundle weight:** Use CDN-hosted libraries (like Plotly CDN or unpkg) rather than inlining massive 5 MB JavaScript libraries directly into the HTML document.
- **Check tablet responsiveness:** Test chart reflow on mobile and tablet viewport widths to ensure axis labels and legends remain readable.

---

## Frequently asked questions

### Can I share dashboards that rely on multiple files or images?
Yes. If your dashboard uses local stylesheets, JavaScript files, or embedded images, place them in a folder with `index.html` at the root, compress the folder into a standard `.zip` file, and upload the archive.

### Does the client need to install Python or R?
No. Static HTML dashboards run entirely inside the client’s browser using client-side JavaScript. The recipient does not need any specialized software.

### Can I update the dashboard when new data arrives?
Yes. With FastShared Pro, you can push updated data to the existing URL, preserving the same link for your client.

---

## Share your next dashboard with clarity

Turn your Plotly, Observable, or Quarto files into live, interactive client links in seconds. 

[Publish your dashboard on FastShared](https://fastsha.red)
