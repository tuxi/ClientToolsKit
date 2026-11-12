#!/usr/bin/env python3
"""Render the curated UI benchmark and export DOM-derived ground truth.

The truth is captured from browser layout, never from the inspected OCR/vision
output. Re-running this script changes the dataset and therefore requires an
explicit new baseline directory rather than an in-place baseline refresh.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DATASET = ROOT / "dataset"
IMAGES = DATASET / "images"
GROUND_TRUTH = DATASET / "ground_truth"


def icon(name: str) -> str:
    paths = {
        "home": '<path d="M3 10.5 12 3l9 7.5V21h-6v-6H9v6H3z"/>',
        "feed": '<path d="M4 4h16v4H4zm0 6h16v10H4z"/>',
        "search": '<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>',
        "settings": '<circle cx="12" cy="12" r="3"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10 2 2M19 5l-2 2M7 17l-2 2"/>',
        "bell": '<path d="M6 17h12l-2-3V9a4 4 0 0 0-8 0v5z"/><path d="M10 20h4"/>',
        "chevron": '<path d="m9 18 6-6-6-6"/>',
        "check": '<path d="m5 12 4 4L19 6"/>',
        "plus": '<path d="M12 5v14M5 12h14"/>',
        "filter": '<path d="M4 5h16l-6 7v6l-4 2v-8z"/>',
        "card": '<rect x="2" y="5" width="20" height="14" rx="3"/><path d="M2 10h20"/>',
        "bolt": '<path d="m13 2-8 12h7l-1 8 8-12h-7z"/>',
        "more": '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
        "mail": '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>',
        "calendar": '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4m8-4v4"/>',
    }
    return f'<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">{paths[name]}</svg>'


def shell(title: str, body: str, active: str = "Home", dark: bool = False, wide: bool = False) -> str:
    nav_items = [
        ("home", "Home"),
        ("feed", "Feed"),
        ("search", "Explore"),
        ("settings", "Settings"),
    ]
    nav = "".join(
        f'<a class="nav-item {"active" if label == active else ""}">{icon(key)}<span>{label}</span></a>'
        for key, label in nav_items
    )
    return f"""
    <div class="app {'dark' if dark else ''} {'wide' if wide else ''}">
      <aside class="sidebar" data-gt-container="sidebar">
        <div class="brand"><span class="brand-mark">C</span><span>Cloudbase</span></div>
        <nav>{nav}</nav>
        <div class="nav-footer">
          <a class="nav-item">{icon('bell')}<span>Notifications</span><b class="count">7</b></a>
          <div class="profile-chip"><span class="avatar">AM</span><span><strong>Alex Morgan</strong><small>Product team</small></span></div>
        </div>
      </aside>
      <main class="main">
        <header class="topbar" data-gt-container="topbar">
          <div><small class="eyebrow">Cloudbase / Workspace</small><h2>{title}</h2></div>
          <div class="topbar-actions">
            <label class="searchbox" data-gt-container="global_search">{icon('search')}<input placeholder="Search anything" value="Projects, people, files" /></label>
            <button class="button ghost">{icon('bell')} Updates</button>
            <button class="button primary">{icon('plus')} New</button>
          </div>
        </header>
        <section class="content">{body}</section>
      </main>
    </div>
    """


def settings_general() -> str:
    rows = [
        ("Workspace name", "Cloudbase Design", "Shown in shared links and invitations."),
        ("Language", "English (United States)", "Applies to menus, alerts, and exports."),
        ("Time zone", "Asia/Shanghai (GMT+8)", "Used for activity history and schedules."),
        ("Start week on", "Monday", "Calendar and report grouping preference."),
        ("Compact mode", "Off", "Reduce spacing across dense tables."),
        ("Automatic updates", "On", "Install stable releases automatically."),
    ]
    row_html = "".join(
        f'<div class="setting-row" data-gt-container="setting_{i}"><div><span class="gt-row-label">{label}</span><p>{hint}</p></div><button class="select">{value}{icon("chevron")}</button></div>'
        for i, (label, value, hint) in enumerate(rows)
    )
    return f"""
    <div class="toolbar-strip" data-gt-container="settings_toolbar">
      <strong>General</strong><span class="muted">Workspace preferences</span>
      <button class="button ghost">{icon('filter')} Filter</button><button class="button primary">{icon('check')} Save changes</button>
    </div>
    <div class="settings-layout">
      <aside class="settings-nav" data-gt-container="settings_nav">
        <a class="selected">General</a><a>Members</a><a>Billing</a><a>Integrations</a><a>Security</a><a>Advanced</a>
      </aside>
      <div class="card settings-card" data-gt-container="settings_panel" data-gt-group="setting_rows" data-gt-group-axis="vertical">
        <div class="panel-heading"><div><h3>Workspace settings</h3><p>Manage defaults for everyone in this workspace.</p></div><span class="pill success">Synced</span></div>
        {row_html}
      </div>
    </div>
    """


def settings_privacy() -> str:
    controls = [
        ("Two-factor authentication", "Required for admins", True),
        ("Session timeout", "30 minutes", False),
        ("Download audit log", "Last export 2 days ago", False),
        ("Device approvals", "3 active devices", False),
        ("Location history", "Retention: 90 days", True),
    ]
    rows = "".join(
        f'<div class="security-row" data-gt-container="security_{i}"><div class="security-icon">{icon("settings")}</div><div><span class="gt-row-label">{name}</span><p>{detail}</p></div><b class="switch {"on" if enabled else ""}"></b></div>'
        for i, (name, detail, enabled) in enumerate(controls)
    )
    return f"""
    <div class="page-head"><div><span class="eyebrow">Security center</span><h1>Privacy & access</h1><p>Review active sessions, authentication, and audit controls.</p></div><button class="button primary">Review recommendations</button></div>
    <div class="metric-grid compact">
      <div class="metric" data-gt-container="risk_metric"><span>Risk score</span><strong>Low</strong><small>12 checks passed</small></div>
      <div class="metric" data-gt-container="session_metric"><span>Active sessions</span><strong>3</strong><small>1 mobile, 2 desktop</small></div>
      <div class="metric" data-gt-container="audit_metric"><span>Audit events</span><strong>1,284</strong><small>Last 30 days</small></div>
    </div>
    <div class="card security-card" data-gt-container="security_panel" data-gt-group="security_rows" data-gt-group-axis="vertical">{rows}</div>
    """


def feed_social() -> str:
    posts = [
        ("Maya Chen", "Design Systems", "Shipping a quieter navigation system today. The biggest win was removing options, not adding them.", "2m", "128"),
        ("Jon Bell", "Research", "Five observations from testing onboarding with first-time admins in Manila and Berlin.", "18m", "64"),
        ("Priya Raman", "Engineering", "The new evidence viewer is live in staging. Crop integrity checks now run before every render.", "41m", "93"),
        ("Theo Park", "Product", "Weekly metrics are in: activation is up 7.4%, and time to first value is down to 6m 12s.", "1h", "47"),
    ]
    cards = "".join(
        f'''<article class="post" data-gt-container="post_{i}">
          <div class="avatar">{name.split()[0][0]}{name.split()[1][0]}</div>
          <div class="post-body"><div class="post-head"><strong>{name}</strong><span class="badge">{team}</span><span class="muted">{age}</span></div>
          <p>{copy}</p><div class="post-art art-{i}"><span>{team} notes</span></div>
          <footer><button>Like · {likes}</button><button>Comment</button><button>Share</button><button class="mt-auto">{icon('more')}</button></footer></div>
        </article>'''
        for i, (name, team, copy, age, likes) in enumerate(posts)
    )
    return f"""
    <div class="feed-grid">
      <div class="feed-column" data-gt-group="feed_posts" data-gt-group-axis="vertical">{cards}</div>
      <aside class="right-rail">
        <div class="card" data-gt-container="suggested_people"><h3>People to follow</h3><div class="person"><span class="avatar">LS</span><span><strong>Lina Soto</strong><small>Staff designer</small></span><button class="mini">Follow</button></div><div class="person"><span class="avatar">RK</span><span><strong>Ravi Kumar</strong><small>Data science</small></span><button class="mini">Follow</button></div><div class="person"><span class="avatar">NW</span><span><strong>Noah Williams</strong><small>Frontend platform</small></span><button class="mini">Follow</button></div></div>
        <div class="card" data-gt-container="trending"><h3>Trending in design</h3><p class="trend">#EvidenceFirst <small>2.4k posts</small></p><p class="trend">#QuietInterfaces <small>1.8k posts</small></p><p class="trend">#Accessibility <small>1.2k posts</small></p></div>
      </aside>
    </div>
    """


def feed_news() -> str:
    stories = [
        ("Markets", "Chipmakers lead a cautious rebound after overnight losses", "Global desks remain focused on supply guidance and demand visibility into next quarter.", "6 min read"),
        ("Cities", "A transit network rebuild inches toward its first passenger milestone", "Engineers completed overnight tests on the eastern corridor earlier this week.", "4 min read"),
        ("Science", "Researchers map how urban trees change peak summer temperatures", "Street-level sensors recorded differences of up to 3.2 degrees across neighborhoods.", "7 min read"),
        ("Culture", "Independent cinemas test a shared membership model", "Eight venues will offer cross-city access in a six-month pilot starting Friday.", "3 min read"),
    ]
    cards = "".join(
        f'''<article class="news-card" data-gt-container="story_{i}"><div class="news-image art-news-{i}"></div><div><span class="kicker">{section}</span><h3>{headline}</h3><p>{deck}</p><small>{read}</small></div></article>'''
        for i, (section, headline, deck, read) in enumerate(stories)
    )
    return f"""
    <div class="news-top"><div><span class="eyebrow">Morning briefing</span><h1>What matters today</h1><p>Curated reporting from 24 newsrooms, updated at 08:30.</p></div><div class="segmented"><button class="active">For you</button><button>World</button><button>Technology</button></div></div>
    <div class="news-layout"><div class="news-lead" data-gt-container="lead_story"><div class="lead-image"></div><span class="kicker">Analysis</span><h2>The next phase of the AI platform race is about distribution</h2><p>Enterprise buyers are consolidating vendors, and the advantage is shifting from raw model quality to deployment reach.</p><small>By Jordan Lee · 8 min read</small></div><div class="news-list" data-gt-group="news_stories" data-gt-group-axis="vertical">{cards}</div></div>
    """


def editor_document() -> str:
    toolbar = [
        ("undo", "Undo"), ("redo", "Redo"), ("heading", "Heading"), ("bold", "Bold"), ("link", "Link"), ("comment", "Comment"), ("more", "More")
    ]
    tools = "".join(f'<button data-gt-group-member>{icon("check")}<span>{label}</span></button>' for _, label in toolbar)
    return f"""
    <div class="editor-toolbar" data-gt-container="editor_toolbar" data-gt-group="editor_tools" data-gt-group-axis="horizontal">{tools}<span class="save-state">Saved just now</span></div>
    <div class="editor-layout">
      <aside class="outline" data-gt-container="document_outline"><h3>Outline</h3><a class="active">Overview</a><a>Customer problem</a><a>Evidence collected</a><a>Proposed workflow</a><a>Launch checklist</a><a>Appendix</a></aside>
      <article class="paper" data-gt-container="document_sheet"><span class="eyebrow">Product brief · Draft 4</span><h1>Evidence-first interface review</h1><p class="lede">A review of how teams inspect, compare, and decide from visual evidence without asking a model to invent structure.</p><h2>Customer problem</h2><p>Product teams can capture screenshots faster than they can agree on what the screenshot proves. Reviews drift into subjective descriptions, and the evidence trail is lost between design, engineering, and research.</p><blockquote>Measure the observable facts first. Keep every inference editable and visibly uncertain.</blockquote><h2>Evidence collected</h2><ul><li>28 representative interface states</li><li>Manual OCR and geometry labels</li><li>Source and crop integrity checks</li></ul></article>
      <aside class="comments" data-gt-container="comments_panel"><h3>Comments · 3</h3><div class="comment"><span class="avatar small">MC</span><p><strong>Maya</strong> Keep the integrity section before latency.</p></div><div class="comment"><span class="avatar small">JB</span><p><strong>Jon</strong> Are these crop bounds normalized?</p></div></aside>
    </div>
    """


def editor_code() -> str:
    lines = [
        ("12", "func inspect(source: Image) async throws -> Evidence {"),
        ("13", "    let decoded = try decode(source)"),
        ("14", "    guard decoded.width > 0 else {"),
        ("15", "        throw EvidenceError.emptySource"),
        ("16", "    }"),
        ("17", "    let text = try await ocr(decoded)"),
        ("18", "    let boxes = try detectRectangles(decoded)"),
        ("19", "    return Evidence(text: text, boxes: boxes)"),
        ("20", "}"),
    ]
    code = "".join(f'<div class="code-line"><span>{number}</span><code>{line}</code></div>' for number, line in lines)
    return f"""
    <div class="ide">
      <aside class="file-tree" data-gt-container="file_tree"><h3>Explorer</h3><strong>EVIDENCE</strong><a class="active">InspectSource.swift</a><a>EvidenceModel.swift</a><a>CropValidator.swift</a><a>Runner.swift</a><strong>TESTS</strong><a>InspectSourceTests.swift</a><a>FixtureTests.swift</a></aside>
      <section class="code-panel" data-gt-container="code_panel"><div class="tabs"><button class="active">InspectSource.swift</button><button>EvidenceModel.swift</button><button>Runner.swift</button></div><div class="code-area">{code}</div><div class="console"><strong>PROBLEMS</strong><span>0 errors</span><span>2 warnings</span><p>warning: Source image has low contrast near the bottom edge.</p></div></section>
      <aside class="inspector" data-gt-container="code_inspector"><h3>Inspector</h3><label>Target<select><option>UIEvidenceBenchmarkRunner</option></select></label><label>Configuration<select><option>Debug</option></select></label><div class="inspector-note">Swift 6.1 · macOS 15</div></aside>
    </div>
    """


def form_checkout() -> str:
    fields = [
        ("Email address", "alex.morgan@example.com"), ("Full name", "Alex Morgan"),
        ("Company", "Northstar Studio"), ("Tax ID", "US-4821-9902"),
    ]
    inputs = "".join(f'<label class="field"><span>{label}</span><input value="{value}" /></label>' for label, value in fields)
    return f"""
    <div class="checkout-layout">
      <section class="form-card card" data-gt-container="checkout_form"><div class="steps"><span class="done">1 Account</span><span class="active">2 Billing</span><span>3 Review</span></div><h1>Billing details</h1><p class="muted">Your receipt and invoices will be sent to this address.</p><div class="form-grid">{inputs}<label class="field span-2"><span>Billing address</span><input value="88 King Street, San Francisco, CA 94107" /></label><label class="check"><input type="checkbox" checked /> Use this address for tax calculation</label></div></section>
      <aside class="summary card" data-gt-container="order_summary"><div class="summary-title"><h3>Order summary</h3><span class="pill">Annual</span></div><div class="summary-line"><span>Cloudbase Team</span><strong>$1,188.00</strong></div><div class="summary-line"><span>Additional storage</span><strong>$120.00</strong></div><div class="summary-line"><span>Tax</span><strong>$105.84</strong></div><div class="summary-line total"><span>Total due today</span><strong>$1,413.84</strong></div><button class="button primary wide">Continue to payment</button><small>Secure checkout · Cancel anytime</small></aside>
    </div>
    """


def form_profile() -> str:
    return f"""
    <div class="mobile-shell">
      <header class="mobile-head"><button>Cancel</button><strong>Edit profile</strong><button class="text-button">Save</button></header>
      <div class="avatar large">AM</div><button class="link-button">Change photo</button>
      <div class="mobile-form" data-gt-container="profile_form">
        <label class="field"><span>First name</span><input value="Alex" /></label>
        <label class="field"><span>Last name</span><input value="Morgan" /></label>
        <label class="field"><span>Email</span><input value="alex@cloudbase.dev" /></label>
        <label class="field"><span>Role</span><select><option>Product designer</option></select></label>
        <label class="field"><span>Bio</span><textarea>Designing calmer tools for complex teams.</textarea></label>
      </div>
      <div class="settings-inline" data-gt-container="profile_preferences"><span>Show profile in search</span><b class="switch on"></b></div>
      <div class="settings-inline"><span>Allow direct messages</span><b class="switch"></b></div>
      <p class="danger-link">Deactivate account</p>
    </div>
    """


def payment_card() -> str:
    methods = [("card", "Visa ending in 4242", "Expires 09/29", True), ("bank", "Business bank account", "ACH · 4–6 business days", False), ("invoice", "Invoice", "Net 30 for approved accounts", False)]
    method_html = "".join(f'<div class="payment-method {"selected" if selected else ""}" data-gt-container="method_{i}"><span class="radio {"on" if selected else ""}"></span><div><strong>{name}</strong><p>{detail}</p></div></div>' for i, (_, name, detail, selected) in enumerate(methods))
    return f"""
    <div class="payment-layout">
      <section class="card payment-card" data-gt-container="payment_panel"><span class="eyebrow">Final step</span><h1>Payment method</h1><p>Select how you would like to pay for the Team plan.</p><div class="payment-methods" data-gt-group="payment_methods" data-gt-group-axis="vertical">{method_html}</div><div class="demo-card" data-gt-container="credit_card"><div class="card-top"><span>Cloudbase</span><span>{icon('card')}</span></div><strong>••••  ••••  ••••  4242</strong><div class="card-bottom"><span>ALEX MORGAN</span><span>09/29</span></div></div><button class="button primary wide">Pay $1,413.84</button><p class="center muted small">By paying, you agree to the Subscription Terms.</p></section>
      <aside class="card receipt" data-gt-container="receipt"><h3>You're paying</h3><div class="total-display">$1,413.84</div><p>Team plan, billed annually</p><div class="summary-line"><span>Subtotal</span><strong>$1,308.00</strong></div><div class="summary-line"><span>Tax</span><strong>$105.84</strong></div><div class="secure-note">{icon('check')} Encrypted payment · 3-D Secure ready</div></aside>
    </div>
    """


def payment_confirm() -> str:
    return f"""
    <div class="mobile-shell payment-mobile">
      <header class="mobile-head"><button>Back</button><strong>Confirm payment</strong><span></span></header>
      <div class="mobile-card" data-gt-container="payment_summary"><span class="eyebrow">Cloudbase Team</span><h1>$1,413.84</h1><p>Annual billing · Renews Oct 12, 2027</p></div>
      <div class="mobile-list" data-gt-container="payment_details"><div><span>Payment method</span><strong>Visa · 4242</strong></div><div><span>Billing email</span><strong>alex@cloudbase.dev</strong></div><div><span>Billing address</span><strong>88 King Street</strong></div><div><span>Promo code</span><button class="link-button">Add</button></div></div>
      <div class="notice">Your card will be charged today. You can cancel or change seats at any time.</div>
      <button class="button primary mobile-wide">Pay $1,413.84</button>
      <p class="center muted small">Secured by Cloudbase Payments</p>
    </div>
    """


def dashboard_analytics() -> str:
    bars = [52, 62, 58, 70, 64, 76, 84, 80, 92, 88, 96, 102]
    graph = "".join(f'<i style="height:{value}px"></i>' for value in bars)
    rows = [("Activation", "72.4%", "+7.1%"), ("Retention", "64.8%", "+2.3%"), ("Expansion", "$48.2k", "+11.6%"), ("Support load", "3.1%", "-0.8%")]
    table = "".join(f'<tr><td>{name}</td><td><strong>{value}</strong></td><td class="good">{delta}</td></tr>' for name, value, delta in rows)
    return f"""
    <div class="page-head"><div><span class="eyebrow">Last 30 days</span><h1>Product overview</h1><p>Acquisition, engagement, and expansion across the team workspace.</p></div><div class="segmented"><button>7d</button><button class="active">30d</button><button>90d</button></div></div>
    <div class="metric-grid"><div class="metric" data-gt-container="mrr"><span>Monthly recurring revenue</span><strong>$248.6k</strong><small class="good">+12.4% vs previous</small></div><div class="metric" data-gt-container="users"><span>Weekly active users</span><strong>18,420</strong><small class="good">+8.9% vs previous</small></div><div class="metric" data-gt-container="nps"><span>NPS</span><strong>54</strong><small class="good">+6 points</small></div><div class="metric"><span>Open incidents</span><strong>2</strong><small>Both under monitoring</small></div></div>
    <div class="dashboard-grid"><section class="card chart-card" data-gt-container="growth_chart"><div class="panel-heading"><div><h3>Weekly active users</h3><p>Unique users who completed a meaningful action.</p></div><span class="pill success">Live</span></div><div class="axis-labels"><span>20k</span><span>15k</span><span>10k</span><span>5k</span></div><div class="bar-chart" data-gt-group="weekly_bars" data-gt-group-axis="horizontal">{graph}</div><div class="chart-labels"><span>Oct 12</span><span>Oct 19</span><span>Oct 26</span><span>Nov 2</span><span>Nov 9</span></div></section><section class="card table-card" data-gt-container="metric_table"><h3>Health metrics</h3><table><thead><tr><th>Metric</th><th>Current</th><th>Change</th></tr></thead><tbody>{table}</tbody></table></section></div>
    """


def dashboard_ops() -> str:
    services = [("Gateway", "99.99%", "Operational"), ("Evidence API", "99.97%", "Operational"), ("Media processing", "99.82%", "Degraded"), ("Notification fanout", "99.95%", "Operational")]
    cards = "".join(f'<div class="service" data-gt-container="service_{i}"><div><strong>{name}</strong><p>p95 latency 182 ms</p></div><span class="status {"warn" if status == "Degraded" else ""}">{status}</span><small>{uptime}</small></div>' for i, (name, uptime, status) in enumerate(services))
    return f"""
    <div class="page-head"><div><span class="eyebrow">Operations · Live</span><h1>System health</h1><p>Service availability and incident status across production regions.</p></div><button class="button primary">Create incident</button></div>
    <div class="ops-grid"><section class="card service-panel" data-gt-container="service_panel" data-gt-group="service_rows" data-gt-group-axis="vertical"><div class="panel-heading"><h3>Core services</h3><span class="pill success">All regions</span></div>{cards}</section><section class="card region-panel" data-gt-container="regions"><h3>Traffic by region</h3><div class="region-row"><span>US West</span><b>38%</b><i><em style="width:38%"></em></i></div><div class="region-row"><span>US East</span><b>27%</b><i><em style="width:27%"></em></i></div><div class="region-row"><span>Europe</span><b>21%</b><i><em style="width:21%"></em></i></div><div class="region-row"><span>Asia Pacific</span><b>14%</b><i><em style="width:14%"></em></i></div></section></div>
    <section class="card incident-card" data-gt-container="incidents"><h3>Recent incidents</h3><table><thead><tr><th>Incident</th><th>Severity</th><th>Status</th><th>Duration</th></tr></thead><tbody><tr><td>Media queue backlog in eu-central</td><td><span class="pill warn">SEV-2</span></td><td>Monitoring</td><td>42m</td></tr><tr><td>Delayed notification delivery</td><td><span class="pill">SEV-3</span></td><td>Resolved</td><td>1h 18m</td></tr><tr><td>Elevated API latency</td><td><span class="pill">SEV-3</span></td><td>Resolved</td><td>26m</td></tr></tbody></table></section>
    """


def modal_delete() -> str:
    return f"""
    <div class="underlay"><div class="page-head"><h1>Project settings</h1><p>Manage the Atlas migration workspace.</p></div><div class="card blurred-card"><h3>Danger zone</h3><p>Deleting a project permanently removes its files, history, and integrations.</p><button class="button danger-outline">Delete project</button></div></div>
    <div class="modal-backdrop"><div class="modal" data-gt-container="delete_modal"><div class="modal-icon danger">{icon('bell')}</div><h2>Delete Atlas migration?</h2><p>This action cannot be undone. 14 files, 3 integrations, and all activity history will be permanently removed.</p><label class="field"><span>Type <strong>ATLAS MIGRATION</strong> to confirm</span><input placeholder="Project name" /></label><div class="modal-actions"><button class="button ghost">Cancel</button><button class="button danger">Delete project</button></div></div></div>
    """


def sheet_filters() -> str:
    return f"""
    <div class="mobile-shell dimmed"><header class="mobile-head"><button>Cancel</button><strong>Search</strong><button class="text-button">Reset</button></header><div class="mobile-search">{icon('search')}<span>Design systems</span></div><div class="skeleton"></div><div class="skeleton short"></div></div>
    <div class="sheet-backdrop"><section class="sheet" data-gt-container="filter_sheet"><div class="grabber"></div><div class="panel-heading"><div><h2>Filters</h2><p>Refine your search results</p></div><button class="text-button">Clear all</button></div><div class="filter-section"><h3>Content type</h3><div class="chips"><button class="chip active">{icon('check')} All</button><button class="chip">Documents</button><button class="chip">Images</button><button class="chip">Videos</button></div></div><div class="filter-section"><h3>Updated</h3><div class="chips"><button class="chip">Today</button><button class="chip active">This week</button><button class="chip">This month</button><button class="chip">Any time</button></div></div><div class="filter-section"><h3>Owner</h3><div class="owner-row"><span class="avatar small">AM</span><span>Alex Morgan</span><b class="switch on"></b></div><div class="owner-row"><span class="avatar small">MC</span><span>Maya Chen</span><b class="switch"></b></div></div><button class="button primary mobile-wide">Show 126 results</button></section></div>
    """


def list_orders() -> str:
    orders = [
        ("#10482", "Northstar Studio", "Paid", "$1,413.84", "Nov 12, 2026"), ("#10481", "Kite & Co.", "Processing", "$288.00", "Nov 12, 2026"),
        ("#10480", "Ravi Kumar", "Paid", "$49.00", "Nov 11, 2026"), ("#10479", "Aster Labs", "Refunded", "$612.00", "Nov 11, 2026"),
        ("#10478", "Mina Okafor", "Paid", "$89.00", "Nov 10, 2026"), ("#10477", "Harbor Health", "Paid", "$2,304.00", "Nov 10, 2026"),
    ]
    rows = "".join(f'<tr data-gt-container="order_{i}"><td><strong>{number}</strong><small>{date}</small></td><td><span class="gt-row-label">{customer}</span></td><td><span class="status {"warn" if status == "Processing" else ""}">{status}</span></td><td>{amount}</td><td><button class="icon-button">{icon("more")}</button></td></tr>' for i, (number, customer, status, amount, date) in enumerate(orders))
    return f"""
    <div class="page-head"><div><span class="eyebrow">Commerce</span><h1>Orders</h1><p>Review recent purchases, refunds, and fulfillment status.</p></div><div><button class="button ghost">{icon('filter')} Filter</button><button class="button primary">{icon('plus')} New order</button></div></div>
    <div class="card table-shell" data-gt-container="orders_table"><div class="table-tools"><label class="searchbox">{icon('search')}<input placeholder="Search orders" /></label><span class="muted">6 of 1,284 orders</span></div><table><thead><tr><th>Order</th><th>Customer</th><th>Status</th><th>Amount</th><th></th></tr></thead><tbody data-gt-group="order_rows" data-gt-group-axis="vertical">{rows}</tbody></table><div class="pagination"><button>Previous</button><span>Page 1 of 214</span><button>Next</button></div></div>
    """


def list_notifications() -> str:
    items = [
        ("Maya mentioned you", "Can you review the crop integrity section?", "2m"), ("Build completed", "Runner v1.8 passed 184 tests.", "18m"),
        ("Payment received", "Northstar Studio paid invoice #10482.", "1h"), ("Access request", "Theo Park requested editor access.", "3h"),
        ("Weekly report ready", "Product overview · Nov 5–11.", "8h"), ("New comment", "Jon replied in Evidence-first review.", "1d"),
    ]
    rows = "".join(f'<div class="notification {"unread" if i < 3 else ""}" data-gt-container="notification_{i}"><span class="notification-icon">{icon("bell")}</span><div><strong>{title}</strong><p>{body}</p></div><span class="gt-row-label muted">{age}</span></div>' for i, (title, body, age) in enumerate(items))
    return f"""
    <div class="mobile-shell"><header class="mobile-head"><button>Home</button><strong>Notifications</strong><button class="text-button">Mark all read</button></header><div class="segmented mobile-tabs"><button class="active">All</button><button>Mentions</button><button>System</button></div><div class="notification-list" data-gt-group="notification_rows" data-gt-group-axis="vertical">{rows}</div></div>
    """


def search_results() -> str:
    results = [
        ("Design evidence guidelines", "docs.cloudbase.dev / handbook", "How teams collect, label, and review visual evidence for product decisions.", "Updated 2 days ago"),
        ("Evidence API reference", "docs.cloudbase.dev / api", "Endpoints for source validation, OCR blocks, container geometry, and crops.", "Updated 1 week ago"),
        ("Q4 design review recording", "cloudbase.dev / media", "A 42-minute review of the evidence viewer and benchmark plan.", "Oct 28, 2026"),
        ("Crop integrity checklist", "cloudbase.dev / engineering", "Pixel bounds, source ancestry, decode checks, and failure escalation.", "Sep 16, 2026"),
    ]
    rows = "".join(f'<article class="result" data-gt-container="result_{i}"><div class="result-icon">{icon("feed")}</div><div><span class="muted">{source}</span><h3>{title}</h3><p>{snippet}</p><small>{updated}</small></div></article>' for i, (title, source, snippet, updated) in enumerate(results))
    return f"""
    <div class="search-page"><div class="search-hero"><div class="big-search" data-gt-container="search_field">{icon('search')}<span>evidence</span><button class="button ghost">{icon('filter')} Filters</button></div><div class="tabs"><button class="active">All</button><button>Documents</button><button>People</button><button>Messages</button><button>Files</button></div></div><p class="result-count">About 1,240 results · 0.18 seconds</p><div class="search-layout"><div class="results" data-gt-group="search_results" data-gt-group-axis="vertical">{rows}</div><aside class="card" data-gt-container="search_help"><h3>Search tips</h3><p>Use quotes for exact phrases.</p><p>Add <b>from:alex</b> to filter by author.</p><p>Add <b>after:2026-10-01</b> for recent items.</p></aside></div></div>
    """


def search_empty() -> str:
    return f"""
    <div class="search-page"><div class="search-hero"><div class="big-search" data-gt-container="search_field">{icon('search')}<span>quarterly retrospective.pdf</span><button class="button primary">Search</button></div><div class="tabs"><button class="active">All</button><button>Documents</button><button>People</button><button>Messages</button><button>Files</button></div></div><div class="empty-state" data-gt-container="empty_state"><div class="empty-icon">{icon('search')}</div><h2>No results for “quarterly retrospective.pdf”</h2><p>Try a broader phrase, check the spelling, or search another workspace.</p><div class="empty-actions"><button class="button primary">Clear filters</button><button class="button ghost">Search Cloudbase support</button></div><div class="recent-searches"><span>Recent searches</span><button>Q4 roadmap</button><button>evidence crops</button><button>Maya Chen</button></div></div></div>
    """


def split_mail() -> str:
    messages = [
        ("Maya Chen", "Crop review notes", "The updated bounds look correct on both mobile and desktop.", "09:42"), ("Jon Bell", "Benchmark dataset", "I reviewed the coverage matrix. The low-contrast cases are useful.", "08:16"), ("Priya Raman", "Runner v1.8", "All integrity checks are green in the latest build.", "Yesterday"), ("Theo Park", "Weekly planning", "Sharing the agenda before tomorrow's review.", "Yesterday"), ("Lina Soto", "Accessibility audit", "Two labels still need a contrast pass.", "Mon"), ("Noah Williams", "API contract", "Freezing v1 now, no schema changes after Friday.", "Sun")
    ]
    rows = "".join(f'<div class="mail-row {"active" if i == 0 else ""}"><div><strong>{sender}</strong><span>{when}</span></div><b>{subject}</b><p>{preview}</p></div>' for i, (sender, subject, preview, when) in enumerate(messages))
    return f"""
    <div class="mail-app"><aside class="mail-folders" data-gt-container="mail_folders"><button class="compose">{icon('plus')} Compose</button><a class="active">{icon('mail')} Inbox <b>7</b></a><a>Starred</a><a>Sent</a><a>Drafts <b>3</b></a><a>Archive</a></aside><section class="mail-list" data-gt-container="message_list" data-gt-group="mail_rows" data-gt-group-axis="vertical"><div class="mail-head"><h2>Inbox</h2><label class="searchbox">{icon('search')}<input placeholder="Search mail" /></label></div>{rows}</section><article class="mail-reader" data-gt-container="mail_reader"><div class="reader-toolbar"><button>Archive</button><button>Delete</button><button>Reply</button><button class="icon-button">{icon('more')}</button></div><span class="eyebrow">Product / Evidence review</span><h1>Crop review notes</h1><div class="sender-line"><span class="avatar">MC</span><div><strong>Maya Chen</strong><p>to Alex Morgan · 09:42</p></div></div><p>The updated bounds look correct on both mobile and desktop. I checked the navigation crop, the repeated list area, and the narrow content column.</p><p>One edge case remains: very small text inside the sticky toolbar can produce a box that overlaps two visual regions. Please keep that in the failure report rather than adjusting the detector before the baseline is frozen.</p><blockquote>Measure first. Diagnose after the immutable run is complete.</blockquote><p>Thanks,<br/>Maya</p><div class="reply-box"><span>Reply to Maya...</span><button class="button primary">Send</button></div></article></div>
    """


def split_settings_wide() -> str:
    teams = [("Design", "18 members", True), ("Engineering", "42 members", False), ("Research", "12 members", False), ("Operations", "9 members", False)]
    rows = "".join(f'<div class="team-row" data-gt-container="team_{i}"><span class="avatar">{name[:2].upper()}</span><div><strong>{name}</strong><p>{count}</p></div><span class="pill">{role}</span><button class="icon-button">{icon("more")}</button></div>' for i, (name, count, active) in enumerate(teams) for role in ["Admin" if active else "Member"])
    return f"""
    <div class="wide-settings"><aside class="settings-nav tall" data-gt-container="settings_nav"><h3>Workspace</h3><a>Overview</a><a class="selected">Teams</a><a>Roles</a><a>Permissions</a><a>SSO</a><a>Directory sync</a></aside><section class="teams-panel" data-gt-container="teams_panel"><div class="page-head"><div><h1>Teams and roles</h1><p>Organize people and control access to projects and data.</p></div><button class="button primary">{icon('plus')} Create team</button></div><div class="card" data-gt-group="team_rows" data-gt-group-axis="vertical">{rows}</div></section><aside class="policy-panel card" data-gt-container="policy_panel"><h3>Role policy</h3><p>Admins can manage billing and security. Members can create projects and invite guests.</p><label>Default role<select><option>Member</option></select></label><label>Guest access<select><option>Restricted</option></select></label><button class="button ghost wide">View permission matrix</button></aside></div>
    """


def landscape_media() -> str:
    return f"""
    <div class="media-app"><header class="media-toolbar" data-gt-container="media_toolbar"><strong>Atlas field recordings</strong><span>14 clips · 2.6 GB</span><button class="button ghost">{icon('filter')} Sort</button><button class="button primary">Export selected</button></header><div class="media-grid"><div class="media-main" data-gt-container="media_preview"><div class="preview-frame"><span class="play">▶</span></div><div class="timeline"><span>00:42</span><div><i style="width:68%"></i></div><span>01:18</span></div><div class="media-meta"><div><h2>Morning market — wide</h2><p>4K · ProRes 422 · 24 fps</p></div><button>Review</button><button>Approve</button></div></div><aside class="clip-list" data-gt-container="clip_list" data-gt-group="clip_rows" data-gt-group-axis="vertical"><div class="clip active"><i class="thumb one"></i><span class="gt-row-label">Morning market</span><small>00:42</small></div><div class="clip"><i class="thumb two"></i><span class="gt-row-label">Street interview</span><small>01:18</small></div><div class="clip"><i class="thumb three"></i><span class="gt-row-label">Transit b-roll</span><small>00:57</small></div><div class="clip"><i class="thumb four"></i><span class="gt-row-label">Closing wide</span><small>01:04</small></div></aside></div></div>
    """


def landscape_table() -> str:
    rows_data = [
        ("Northstar Studio", "Enterprise", "184", "$248,600", "12.4%"), ("Aster Labs", "Growth", "92", "$84,200", "8.1%"),
        ("Harbor Health", "Enterprise", "216", "$312,900", "15.8%"), ("Kite & Co.", "Starter", "24", "$8,640", "3.2%"),
        ("Mina Okafor", "Growth", "38", "$41,500", "6.7%"), ("Ravi Kumar", "Starter", "18", "$6,480", "2.9%"),
        ("Cloudline", "Enterprise", "142", "$198,200", "10.1%"), ("Quartz Works", "Growth", "67", "$72,800", "7.4%"),
    ]
    rows = "".join(f'<tr><td><strong>{name}</strong><small>{plan}</small></td><td>{seats}</td><td>{mrr}</td><td class="good">{growth}</td><td><span class="sparkline"><i></i><i></i><i></i><i></i></span></td></tr>' for name, plan, seats, mrr, growth in rows_data)
    return f"""
    <div class="page-head"><div><span class="eyebrow">Finance · November</span><h1>Account revenue</h1><p>Expanded landscape table with sticky headers and dense values.</p></div><div class="segmented"><button class="active">All accounts</button><button>Enterprise</button><button>Growth</button></div></div>
    <div class="card wide-table" data-gt-container="revenue_table"><div class="table-tools"><label class="searchbox">{icon('search')}<input placeholder="Search accounts" /></label><div><button class="button ghost">Export</button><button class="button primary">{icon('plus')} Add account</button></div></div><table><thead><tr><th>Account</th><th>Seats</th><th>MRR</th><th>Growth</th><th>Trend</th></tr></thead><tbody data-gt-group="revenue_rows" data-gt-group-axis="vertical">{rows}</tbody></table><div class="pagination"><span>1–8 of 284</span><button>Previous</button><button>Next</button></div></div>
    """


def small_text_legal() -> str:
    paragraphs = [
        ("1. Scope and acceptance", "These terms govern access to the Cloudbase evaluation workspace and any related documentation, sample data, or benchmark artifacts made available to the customer. By accessing the workspace, the customer accepts these terms on behalf of the organization identified in the order form."),
        ("2. Evaluation license", "Cloudbase grants a limited, non-exclusive, non-transferable license to use the evaluation workspace solely for internal testing, quality assessment, and procurement review during the evaluation period. The customer may not redistribute, sublicense, or use the workspace to provide a competing service."),
        ("3. Data handling", "Customer content remains the property of the customer. Cloudbase processes customer content only to provide the evaluation workspace, maintain security, and diagnose failures. Benchmark images and ground-truth annotations supplied by the customer must not contain sensitive personal information unless a separate data processing addendum is in effect."),
        ("4. Restrictions", "The customer may not reverse engineer the service, bypass usage limits, conduct load testing without written approval, or attempt to access another customer’s data. Outputs generated during evaluation are provided for internal review and may not be represented as production commitments."),
        ("5. Disclaimer", "The evaluation workspace is provided as is. Cloudbase disclaims all warranties, whether express, implied, or statutory, including merchantability, fitness for a particular purpose, and non-infringement. The customer assumes all risks associated with use of the workspace."),
    ]
    content = "".join(f'<section data-gt-container="clause_{i}"><h2>{heading}</h2><p>{copy}</p></section>' for i, (heading, copy) in enumerate(paragraphs))
    return f"""
    <div class="legal-layout"><aside class="legal-toc" data-gt-container="legal_toc"><h3>Contents</h3><a class="active">Scope and acceptance</a><a>Evaluation license</a><a>Data handling</a><a>Restrictions</a><a>Disclaimer</a><a>Limitation of liability</a></aside><article class="legal-doc" data-gt-container="legal_document"><span class="eyebrow">Evaluation terms · Version 2.4</span><h1>Cloudbase evaluation workspace terms</h1><p class="legal-small">Last updated November 1, 2026 · Effective immediately for new evaluations</p><div class="legal-note">This document contains intentionally small body text to exercise OCR under realistic dense-reading conditions.</div>{content}</article></div>
    """


def low_contrast_form() -> str:
    return f"""
    <div class="soft-page"><div class="soft-card" data-gt-container="contrast_form"><span class="soft-eyebrow">Account recovery</span><h1>Confirm your contact details</h1><p>We use these details to help recover access if you lose your sign-in method.</p><label class="soft-field"><span>Recovery email</span><input value="alex.morgan@example.com" /></label><label class="soft-field"><span>Mobile number</span><input value="+1 415 555 0148" /></label><label class="soft-field"><span>Backup contact</span><input value="maya.chen@example.com" /></label><div class="soft-check"><span class="check-box whoops">{icon('check')}</span><span>Send recovery instructions to this address.</span></div><button class="soft-button">Save contact details</button><p class="soft-help">You can update these details at any time in Security settings.</p></div></div>
    """


def repeated_toolbar_calendar() -> str:
    days = []
    for i in range(35):
        day = i - 3
        days.append(f'<div class="calendar-day {"other" if day < 1 or day > 30 else ""} {"today" if day == 12 else ""}"><span>{day if 1 <= day <= 30 else (30 + day if day < 1 else day - 30)}</span><small>{"Standup" if i % 3 == 0 and 1 <= day <= 30 else ""}</small><i></i></div>')
    tools = "".join(f'<button data-gt-group-member>{icon("calendar")}<span>{label}</span></button>' for label in ["Day", "Week", "Month", "Agenda", "Timeline", "Board"])
    return f"""
    <div class="calendar-head"><div><span class="eyebrow">Product calendar</span><h1>November 2026</h1></div><div class="view-toolbar" data-gt-container="calendar_toolbar" data-gt-group="calendar_views" data-gt-group-axis="horizontal">{tools}</div><button class="button primary">{icon('plus')} New event</button></div>
    <div class="calendar-shell" data-gt-container="calendar_grid"><div class="weekdays"><span>Mon</span><span>Tue</span><span>Wed</span><span>Thu</span><span>Fri</span><span>Sat</span><span>Sun</span></div><div class="calendar-grid">{''.join(days)}</div></div>
    """


def scroll_feed_mobile() -> str:
    posts = "".join(f'<article class="mobile-post" data-gt-container="mobile_post_{i}"><div class="post-head"><span class="avatar">{name[:2].upper()}</span><div><strong>{name}</strong><small>{age}</small></div></div><p>{copy}</p><div class="mobile-photo photo-{i}"></div><div class="post-actions"><button>♡ 128</button><button>Comment 14</button><button>Share</button></div></article>' for i, (name, age, copy) in enumerate([
        ("Maya Chen", "2m", "The quiet navigation experiment is holding up across all three accessibility profiles."),
        ("Theo Park", "18m", "A small behind-the-scenes look at this week's design review."),
        ("Ravi Kumar", "42m", "Three charts, one question: where do evidence reviews lose the most time?"),
    ]))
    return f"""
    <div class="mobile-shell mobile-feed"><header class="mobile-head"><strong>Cloudbase</strong><div><button>{icon('search')}</button><button>{icon('bell')}</button></div></header><div class="stories"><span class="story">Your story</span><span class="story">Maya</span><span class="story">Jon</span><span class="story">Theo</span></div><div class="scroll-area" data-gt-container="feed_scroll_region">{posts}</div><nav class="tabbar"><a class="active">Home</a><a>Explore</a><a>Create</a><a>Inbox</a><a>Profile</a></nav></div>
    """


def jpeg_feed_photo() -> str:
    return feed_social().replace('<div class="feed-grid">', '<div class="feed-grid jpeg-feed">', 1)


def jpeg_table_finance() -> str:
    return landscape_table().replace('<div class="page-head">', '<div class="page-head finance-head">', 1)


def modal_payment_mobile() -> str:
    return f"""
    <div class="mobile-shell dimmed"><header class="mobile-head"><button>Cancel</button><strong>Checkout</strong><span></span></header><div class="mobile-card"><h1>$89.00</h1><p>Cloudbase Pro · Monthly</p></div></div><div class="sheet-backdrop"><section class="sheet payment-sheet" data-gt-container="payment_sheet"><div class="grabber"></div><h2>Choose a payment method</h2><div class="payment-method selected" data-gt-container="apple_pay"><span class="radio on"></span><div><strong>Apple Pay</strong><p>Fast and secure</p></div></div><div class="payment-method" data-gt-container="card_pay"><span class="radio"></span><div><strong>Credit or debit card</strong><p>Visa ending in 4242</p></div></div><div class="payment-method" data-gt-container="paypal"><span class="radio"></span><div><strong>PayPal</strong><p>Pay with your PayPal balance</p></div></div><button class="button primary mobile-wide">Continue</button><p class="center muted small">You can change this later in Billing settings.</p></section></div>
    """


def search_command_dark() -> str:
    commands = [("Open settings", "⌘ ,"), ("Search evidence", "⌘ K"), ("New project", "⌘ N"), ("Invite teammate", "⌘ I"), ("View benchmark report", "⌘ B"), ("Toggle inspector", "⌘ ⇧ I")]
    rows = "".join(f'<div class="command-row {"selected" if i == 0 else ""}"><span>{icon("search")}{label}</span><kbd>{shortcut}</kbd></div>' for i, (label, shortcut) in enumerate(commands))
    return f"""
    <div class="command-backdrop"><div class="command-palette" data-gt-container="command_palette"><div class="command-input">{icon('search')}<span>Type a command or search…</span><kbd>esc</kbd></div><small class="command-label">QUICK ACTIONS</small>{rows}<div class="command-footer"><span>↑↓ Navigate</span><span>↵ Select</span><span>esc Close</span></div></div></div>
    """


PAGES: list[dict[str, Any]] = [
    {"id": "settings_general_light", "category": "settings", "tags": ["desktop", "png", "repeated_toolbar", "scroll_region"], "size": [1440, 900], "format": "png", "dark": False, "title": "Settings", "body": settings_general, "active": "Settings"},
    {"id": "settings_privacy_dark", "category": "settings", "tags": ["desktop", "jpeg", "dark", "repeated_group"], "size": [1440, 900], "format": "jpeg", "dark": True, "title": "Privacy & access", "body": settings_privacy, "active": "Settings"},
    {"id": "feed_social_light", "category": "feed", "tags": ["desktop", "png", "repeated_group", "scroll_region"], "size": [1440, 900], "format": "png", "dark": False, "title": "Home", "body": feed_social, "active": "Home"},
    {"id": "feed_news_compact", "category": "feed", "tags": ["desktop", "png", "small_text", "repeated_group"], "size": [1440, 900], "format": "png", "dark": False, "title": "Feed", "body": feed_news, "active": "Feed"},
    {"id": "editor_document_light", "category": "editor", "tags": ["desktop", "png", "repeated_toolbar"], "size": [1440, 900], "format": "png", "dark": False, "title": "Documents", "body": editor_document, "active": "Home"},
    {"id": "editor_code_dark", "category": "editor", "tags": ["desktop", "png", "dark", "small_text"], "size": [1440, 900], "format": "png", "dark": True, "title": "Code", "body": editor_code, "active": "Home"},
    {"id": "form_checkout_desktop", "category": "form", "tags": ["desktop", "png"], "size": [1440, 900], "format": "png", "dark": False, "title": "Checkout", "body": form_checkout, "active": "Home"},
    {"id": "form_profile_mobile", "category": "form", "tags": ["mobile", "png", "scroll_region"], "size": [430, 932], "format": "png", "dark": False, "title": "Profile", "body": form_profile, "active": "Settings", "mobile": True},
    {"id": "payment_card_desktop", "category": "payment", "tags": ["desktop", "png"], "size": [1440, 900], "format": "png", "dark": False, "title": "Billing", "body": payment_card, "active": "Settings"},
    {"id": "payment_confirm_mobile", "category": "payment", "tags": ["mobile", "png"], "size": [430, 932], "format": "png", "dark": False, "title": "Payment", "body": payment_confirm, "active": "Settings", "mobile": True},
    {"id": "dashboard_analytics_light", "category": "dashboard", "tags": ["desktop", "png", "repeated_group"], "size": [1440, 900], "format": "png", "dark": False, "title": "Analytics", "body": dashboard_analytics, "active": "Home"},
    {"id": "dashboard_ops_dark", "category": "dashboard", "tags": ["desktop", "png", "dark", "repeated_group"], "size": [1440, 900], "format": "png", "dark": True, "title": "Operations", "body": dashboard_ops, "active": "Home"},
    {"id": "sheet_delete_modal", "category": "sheet_modal", "tags": ["desktop", "png", "overlay"], "size": [1440, 900], "format": "png", "dark": False, "title": "Projects", "body": modal_delete, "active": "Home"},
    {"id": "sheet_filters_mobile", "category": "sheet_modal", "tags": ["mobile", "png", "overlay", "low_contrast"], "size": [430, 932], "format": "png", "dark": False, "title": "Search", "body": sheet_filters, "active": "Search", "mobile": True},
    {"id": "list_orders_desktop", "category": "list", "tags": ["desktop", "png", "repeated_group", "scroll_region"], "size": [1440, 900], "format": "png", "dark": False, "title": "Orders", "body": list_orders, "active": "Home"},
    {"id": "list_notifications_mobile", "category": "list", "tags": ["mobile", "png", "repeated_group", "scroll_region"], "size": [430, 932], "format": "png", "dark": False, "title": "Notifications", "body": list_notifications, "active": "Home", "mobile": True},
    {"id": "search_results_desktop", "category": "search", "tags": ["desktop", "png", "repeated_group"], "size": [1440, 900], "format": "png", "dark": False, "title": "Search", "body": search_results, "active": "Search"},
    {"id": "search_empty_desktop", "category": "search", "tags": ["desktop", "png", "empty_state"], "size": [1440, 900], "format": "png", "dark": False, "title": "Search", "body": search_empty, "active": "Search"},
    {"id": "split_mail_desktop", "category": "split_view", "tags": ["desktop", "png", "split", "repeated_group", "scroll_region"], "size": [1440, 900], "format": "png", "dark": False, "title": "Mail", "body": split_mail, "active": "Home"},
    {"id": "split_settings_wide", "category": "split_view", "tags": ["desktop", "png", "split", "repeated_group"], "size": [1600, 900], "format": "png", "dark": False, "title": "Teams", "body": split_settings_wide, "active": "Settings", "wide": True},
    {"id": "landscape_media", "category": "landscape", "tags": ["desktop", "png", "landscape", "repeated_group"], "size": [1440, 900], "format": "png", "dark": False, "title": "Media", "body": landscape_media, "active": "Home"},
    {"id": "landscape_table_finance", "category": "landscape", "tags": ["desktop", "png", "landscape", "repeated_group"], "size": [1600, 900], "format": "png", "dark": False, "title": "Revenue", "body": landscape_table, "active": "Home", "wide": True},
    {"id": "small_text_legal", "category": "small_text", "tags": ["desktop", "png", "small_text", "low_contrast", "scroll_region"], "size": [1440, 900], "format": "png", "dark": False, "title": "Evaluation terms", "body": small_text_legal, "active": "Settings"},
    {"id": "low_contrast_form", "category": "low_contrast", "tags": ["desktop", "png", "low_contrast"], "size": [1440, 900], "format": "png", "dark": False, "title": "Recovery", "body": low_contrast_form, "active": "Settings"},
    {"id": "repeated_toolbar_calendar", "category": "repeated_toolbar", "tags": ["desktop", "png", "repeated_toolbar", "repeated_group"], "size": [1440, 900], "format": "png", "dark": False, "title": "Calendar", "body": repeated_toolbar_calendar, "active": "Home"},
    {"id": "scroll_feed_mobile", "category": "scroll_region", "tags": ["mobile", "png", "scroll_region", "repeated_group"], "size": [430, 932], "format": "png", "dark": False, "title": "Home", "body": scroll_feed_mobile, "active": "Home", "mobile": True},
    {"id": "jpeg_feed_photo", "category": "feed", "tags": ["desktop", "jpeg", "artifact_compression"], "size": [1440, 900], "format": "jpeg", "dark": False, "title": "Home", "body": jpeg_feed_photo, "active": "Home"},
    {"id": "jpeg_table_finance", "category": "landscape", "tags": ["desktop", "jpeg", "artifact_compression", "small_text", "repeated_group"], "size": [1600, 900], "format": "jpeg", "dark": False, "title": "Revenue", "body": jpeg_table_finance, "active": "Home", "wide": True},
    {"id": "modal_payment_mobile", "category": "sheet_modal", "tags": ["mobile", "png", "overlay"], "size": [430, 932], "format": "png", "dark": False, "title": "Checkout", "body": modal_payment_mobile, "active": "Settings", "mobile": True},
    {"id": "search_command_dark", "category": "search", "tags": ["desktop", "png", "dark", "overlay"], "size": [1440, 900], "format": "png", "dark": True, "title": "Command", "body": search_command_dark, "active": "Search"},
]

CROPS = [
    {"bbox": {"x": 0.0, "y": 0.0, "width": 0.18, "height": 1.0}, "purpose": "navigation"},
    {"bbox": {"x": 0.18, "y": 0.07, "width": 0.62, "height": 0.85}, "purpose": "content"},
    {"bbox": {"x": 0.62, "y": 0.07, "width": 0.38, "height": 0.42}, "purpose": "detail"},
]

MOBILE_CROPS = [
    {"bbox": {"x": 0.0, "y": 0.0, "width": 1.0, "height": 0.12}, "purpose": "navigation"},
    {"bbox": {"x": 0.04, "y": 0.12, "width": 0.92, "height": 0.68}, "purpose": "content"},
    {"bbox": {"x": 0.04, "y": 0.74, "width": 0.92, "height": 0.20}, "purpose": "controls"},
]


CSS = r"""
:root{--bg:#f5f7fb;--panel:#fff;--ink:#172033;--muted:#6a7488;--line:#dfe4ed;--soft:#eef2f8;--accent:#315efb;--accent-soft:#e9eeff;--good:#16835b;--warn:#ae6a00;--danger:#c33c4a;--shadow:0 12px 36px rgba(23,32,51,.08)}
*{box-sizing:border-box}html,body{margin:0;min-height:100%;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;color:var(--ink);background:var(--bg);-webkit-font-smoothing:antialiased}body{overflow:hidden}button,input,select,textarea{font:inherit}button{cursor:pointer}.icon{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round;flex:0 0 auto}.muted,small{color:var(--muted)}.eyebrow{display:block;text-transform:uppercase;letter-spacing:.12em;font-size:11px;font-weight:700;color:var(--muted);margin-bottom:8px}
.app{height:100vh;display:grid;grid-template-columns:236px 1fr;background:var(--bg)}.sidebar{background:#11182a;color:#f7f9ff;padding:24px 16px;display:flex;flex-direction:column;gap:28px}.brand{display:flex;align-items:center;gap:11px;font-weight:750;font-size:18px;padding:2px 8px}.brand-mark{display:grid;place-items:center;width:30px;height:30px;border-radius:9px;background:linear-gradient(135deg,#7b9cff,#315efb);font-weight:800}nav{display:flex;flex-direction:column;gap:7px}.nav-item{display:flex;align-items:center;gap:11px;padding:11px 12px;color:#aeb9cf;border-radius:9px;font-size:14px}.nav-item.active{background:#26324d;color:white}.nav-footer{margin-top:auto;display:flex;flex-direction:column;gap:18px}.count{margin-left:auto;background:#315efb;border-radius:10px;padding:2px 7px;font-size:11px}.profile-chip{display:flex;gap:10px;align-items:center;border-top:1px solid #2c364d;padding-top:18px}.profile-chip span:last-child{display:flex;flex-direction:column;font-size:13px}.profile-chip small{color:#94a1bb}.avatar{display:grid;place-items:center;width:36px;height:36px;border-radius:50%;background:#dce4ff;color:#2846a5;font-weight:700;font-size:12px;flex:0 0 auto}.avatar.small{width:28px;height:28px;font-size:10px}.avatar.large{width:76px;height:76px;margin:28px auto 10px;font-size:22px}
.main{min-width:0;height:100vh;display:flex;flex-direction:column;overflow:hidden}.topbar{height:74px;padding:0 28px;background:var(--panel);border-bottom:1px solid var(--line);display:flex;align-items:center;justify-content:space-between;flex:0 0 auto}.topbar h2{margin:1px 0 0;font-size:17px}.topbar .eyebrow{margin:0}.topbar-actions{display:flex;align-items:center;gap:10px}.searchbox{display:flex;align-items:center;gap:9px;border:1px solid var(--line);background:#f8faff;border-radius:9px;padding:9px 12px;color:var(--muted)}.searchbox input{border:0;background:transparent;outline:0;width:220px;color:var(--ink);font-size:13px}.button{border:1px solid var(--line);border-radius:9px;background:white;padding:9px 13px;display:inline-flex;align-items:center;justify-content:center;gap:8px;font-weight:650;font-size:13px;color:var(--ink)}.button.primary{background:var(--accent);border-color:var(--accent);color:white}.button.ghost{background:#fff}.button.wide{width:100%}.button.danger{background:var(--danger);border-color:var(--danger);color:white}.button.danger-outline{border-color:#e9aeb4;color:var(--danger);background:#fff7f8}.content{padding:26px 28px;overflow:auto;flex:1;min-height:0}.card{background:var(--panel);border:1px solid var(--line);border-radius:14px;box-shadow:0 4px 14px rgba(23,32,51,.035)}.pill{display:inline-flex;align-items:center;border-radius:999px;background:var(--soft);padding:4px 9px;font-size:11px;font-weight:700}.pill.success{background:#e9f8f1;color:var(--good)}.pill.warn{background:#fff2dc;color:var(--warn)}.status{display:inline-block;border-radius:999px;background:#e9f8f1;color:var(--good);font-size:11px;font-weight:700;padding:5px 9px}.status.warn{background:#fff2dc;color:var(--warn)}.page-head{display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:24px}.page-head h1{font-size:28px;letter-spacing:-.035em;margin:0 0 7px}.page-head p{margin:0;color:var(--muted);font-size:14px}.segmented{display:flex;gap:3px;background:var(--soft);padding:3px;border-radius:9px}.segmented button{border:0;background:transparent;padding:7px 12px;border-radius:7px;color:var(--muted);font-size:12px;font-weight:650}.segmented button.active{background:#fff;color:var(--ink);box-shadow:0 1px 3px rgba(0,0,0,.08)}.panel-heading{display:flex;align-items:flex-start;justify-content:space-between;gap:12px}.panel-heading h3{margin:0 0 5px}.panel-heading p{margin:0;color:var(--muted);font-size:13px}.metric-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-bottom:16px}.metric-grid.compact{grid-template-columns:repeat(3,1fr)}.metric{background:#fff;border:1px solid var(--line);border-radius:13px;padding:18px;display:flex;flex-direction:column;gap:10px}.metric span{font-size:12px;color:var(--muted)}.metric strong{font-size:25px;letter-spacing:-.03em}.metric small{font-size:11px}.good{color:var(--good)!important}
.toolbar-strip{display:flex;align-items:center;gap:16px;margin:-4px 0 18px;padding-bottom:16px;border-bottom:1px solid var(--line)}.toolbar-strip .button{margin-left:0}.toolbar-strip .button.primary{margin-left:auto}.settings-layout{display:grid;grid-template-columns:190px 1fr;gap:18px}.settings-nav{background:transparent;display:flex;flex-direction:column;padding-top:8px}.settings-nav a{padding:9px 12px;font-size:13px;color:var(--muted);border-radius:8px}.settings-nav a.selected{background:var(--accent-soft);color:var(--accent);font-weight:700}.settings-card{padding:22px}.setting-row{display:flex;align-items:center;justify-content:space-between;padding:17px 0;border-top:1px solid var(--line)}.setting-row p{margin:4px 0 0;color:var(--muted);font-size:12px}.select{border:1px solid var(--line);border-radius:8px;background:#fff;padding:9px 11px;display:flex;align-items:center;gap:16px;font-size:12px;color:var(--ink)}.select .icon{width:14px}.security-card{padding:7px 22px}.security-row{display:flex;align-items:center;gap:14px;padding:16px 0;border-bottom:1px solid var(--line)}.security-row:last-child{border-bottom:0}.security-row>div:nth-child(2){flex:1}.security-row p{margin:4px 0 0;color:var(--muted);font-size:12px}.security-icon{width:38px;height:38px;border-radius:10px;background:var(--soft);display:grid;place-items:center}.switch{width:38px;height:22px;border-radius:20px;background:#c9d1df;display:block;position:relative}.switch:after{content:"";position:absolute;width:16px;height:16px;border-radius:50%;background:#fff;top:3px;left:3px;box-shadow:0 1px 2px rgba(0,0,0,.2)}.switch.on{background:var(--accent)}.switch.on:after{left:19px}
.feed-grid{display:grid;grid-template-columns:minmax(0,720px) 300px;gap:20px;justify-content:center}.feed-column{display:flex;flex-direction:column;gap:14px}.post{background:#fff;border:1px solid var(--line);border-radius:14px;padding:17px;display:flex;gap:13px}.post-body{flex:1;min-width:0}.post-head{display:flex;align-items:center;gap:8px}.post-head strong{font-size:13px}.badge{background:var(--soft);padding:3px 7px;border-radius:6px;font-size:10px;color:var(--muted)}.post p{font-size:13px;line-height:1.55;margin:10px 0}.post-art{height:88px;border-radius:10px;background:linear-gradient(120deg,#e8eeff,#d6e9ff 48%,#f4e8ff);display:flex;align-items:flex-end;padding:12px;color:#40527c;font-weight:700;font-size:12px}.art-1{background:linear-gradient(120deg,#e4f4ec,#d2eadf 55%,#edf5d9)}.art-2{background:linear-gradient(120deg,#f5ead8,#f0d9c1 55%,#f7f0e4)}.art-3{background:linear-gradient(120deg,#ede8fb,#dfd8f6 55%,#e9eefc)}.post footer{display:flex;gap:7px;margin-top:12px}.post footer button{border:0;background:transparent;color:var(--muted);font-size:11px;padding:5px 0;margin-right:14px}.mt-auto{margin-left:auto}.right-rail{display:flex;flex-direction:column;gap:14px}.right-rail .card{padding:18px}.right-rail h3{font-size:14px;margin:0 0 14px}.person{display:flex;align-items:center;gap:9px;margin:13px 0}.person>span:nth-child(2){display:flex;flex-direction:column;flex:1;font-size:12px}.person small{font-size:10px}.mini{border:0;background:var(--accent-soft);color:var(--accent);border-radius:7px;padding:6px 9px;font-size:11px;font-weight:700}.trend{font-weight:650;font-size:12px;margin:13px 0}.trend small{font-weight:400;margin-left:8px}
.news-top{display:flex;justify-content:space-between;align-items:flex-end;margin-bottom:20px}.news-top h1{font-size:29px;margin:0 0 7px}.news-top p{margin:0;color:var(--muted);font-size:13px}.news-layout{display:grid;grid-template-columns:1.05fr .95fr;gap:20px}.news-lead{background:#fff;border-radius:14px;overflow:hidden;border:1px solid var(--line)}.lead-image{height:220px;background:linear-gradient(135deg,#243858,#4c759d 50%,#bdc9d2)}.news-lead>div:not(.lead-image){padding:20px}.kicker{font-size:10px;text-transform:uppercase;letter-spacing:.12em;color:var(--accent);font-weight:750}.news-lead h2{font-size:25px;line-height:1.16;margin:8px 0}.news-lead p{font-size:13px;line-height:1.5;color:var(--muted)}.news-list{display:flex;flex-direction:column;gap:10px}.news-card{display:grid;grid-template-columns:110px 1fr;gap:12px;background:#fff;border:1px solid var(--line);border-radius:11px;padding:10px}.news-image{height:86px;border-radius:7px;background:linear-gradient(140deg,#b9c7d9,#61778e)}.art-news-1{background:linear-gradient(140deg,#bea978,#705c3e)}.art-news-2{background:linear-gradient(140deg,#8bb9a7,#3d675b)}.art-news-3{background:linear-gradient(140deg,#c2a7be,#6e496bc)}.news-card h3{font-size:13px;line-height:1.3;margin:5px 0}.news-card p{font-size:11px;color:var(--muted);line-height:1.4;margin:0 0 6px}.news-card small{font-size:10px}
.editor-toolbar{height:52px;background:#fff;border:1px solid var(--line);border-radius:11px;display:flex;align-items:center;gap:2px;padding:0 8px;margin-bottom:12px}.editor-toolbar button{border:0;background:transparent;border-radius:7px;padding:7px;display:flex;align-items:center;gap:5px;font-size:10px;color:var(--muted)}.editor-toolbar .save-state{margin-left:auto;color:var(--muted);font-size:11px}.editor-layout{display:grid;grid-template-columns:150px minmax(480px,1fr) 220px;gap:14px;height:calc(100vh - 164px)}.outline,.comments{background:#fff;border:1px solid var(--line);border-radius:12px;padding:16px}.outline h3,.comments h3{font-size:12px;margin:0 0 12px}.outline a{display:block;font-size:11px;color:var(--muted);padding:7px 8px;border-radius:6px}.outline a.active{background:var(--soft);color:var(--ink)}.paper{background:#fff;border:1px solid var(--line);border-radius:12px;padding:42px 54px;overflow:auto}.paper h1{font-size:32px;letter-spacing:-.04em;margin:6px 0 16px}.paper h2{font-size:19px;margin-top:26px}.paper p,.paper li{font-size:13px;line-height:1.65}.lede{font-size:16px!important;color:var(--muted)}blockquote{border-left:3px solid var(--accent);margin:18px 0;padding:10px 16px;background:var(--accent-soft);font-size:13px}.comment{display:flex;gap:8px;padding:12px 0;border-top:1px solid var(--line)}.comment p{font-size:11px;line-height:1.45;margin:0}.comment strong{display:block}
.ide{display:grid;grid-template-columns:210px 1fr 250px;height:calc(100vh - 126px);border:1px solid #273247;border-radius:12px;overflow:hidden;background:#0e1522;color:#d8e1f2}.file-tree,.inspector{padding:16px;background:#121a29;border-right:1px solid #283349}.file-tree h3,.inspector h3{font-size:12px;text-transform:uppercase;letter-spacing:.1em;margin:0 0 15px;color:#8390a8}.file-tree strong{display:block;font-size:10px;color:#7f8ca3;margin:12px 0 6px}.file-tree a{display:block;padding:7px;border-radius:5px;font-size:11px;color:#aab6ca}.file-tree a.active{background:#243252;color:white}.code-panel{display:flex;flex-direction:column;min-width:0}.tabs{height:42px;display:flex;border-bottom:1px solid #283349}.tabs button{border:0;background:#121a29;color:#8f9bb0;padding:0 16px;font-size:11px}.tabs button.active{background:#0e1522;color:#dce5f4;border-top:2px solid #5d83ff}.code-area{padding:18px 0;flex:1}.code-line{display:grid;grid-template-columns:44px 1fr;font-family:"SFMono-Regular",Menlo,monospace;font-size:12px;line-height:2}.code-line span{text-align:right;padding-right:14px;color:#4f5d77}.code-line code{color:#cdd7e8}.console{border-top:1px solid #283349;padding:12px 16px;font-size:11px}.console strong{font-size:9px;letter-spacing:.12em;color:#8e9bb2;margin-right:14px}.console span{margin-right:16px;color:#9ba8be}.console p{color:#d1ab69}.inspector{border-right:0;border-left:1px solid #283349}.inspector label{display:block;font-size:10px;color:#8f9bb0;margin:14px 0}.inspector select{display:block;width:100%;margin-top:6px;padding:7px;background:#1a2436;border:1px solid #33405a;border-radius:5px;color:#cbd5e5}.inspector-note{font-size:10px;color:#8390a8;border-top:1px solid #283349;padding-top:14px;margin-top:20px}
.checkout-layout,.payment-layout{display:grid;grid-template-columns:minmax(600px,1fr) 360px;gap:20px;max-width:1120px;margin:0 auto}.form-card,.summary,.payment-card,.receipt{padding:26px}.steps{display:flex;gap:28px;color:var(--muted);font-size:12px;margin-bottom:24px}.steps .done{color:var(--good)}.steps .active{color:var(--accent);font-weight:700}.form-card h1,.payment-card h1{font-size:28px;margin:0 0 6px}.form-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-top:24px}.field{display:flex;flex-direction:column;gap:7px;font-size:12px;font-weight:650}.field input,.field select,.field textarea{border:1px solid var(--line);border-radius:8px;padding:10px 11px;background:#fbfcfe;color:var(--ink);outline:0}.span-2{grid-column:1/3}.check{grid-column:1/3;display:flex;gap:8px;align-items:center;color:var(--muted);font-size:12px}.summary-title{display:flex;justify-content:space-between;align-items:center}.summary-line{display:flex;justify-content:space-between;padding:12px 0;border-bottom:1px solid var(--line);font-size:12px}.summary-line.total{font-size:16px;border-bottom:0;margin-top:8px}.summary .button{margin:16px 0 9px}.summary small{display:block;text-align:center;font-size:10px}
.mobile-shell{height:100vh;max-width:430px;margin:0 auto;background:#fff;overflow:hidden;position:relative}.mobile-head{height:54px;padding:0 14px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid var(--line)}.mobile-head button{border:0;background:transparent;font-size:12px;color:var(--accent)}.mobile-head strong{font-size:13px}.text-button{color:var(--accent)!important;font-weight:700}.link-button{border:0;background:transparent;color:var(--accent);display:block;margin:0 auto;font-size:11px}.mobile-form{padding:10px 18px}.mobile-form .field{margin-bottom:14px}.settings-inline{display:flex;justify-content:space-between;align-items:center;padding:14px 18px;border-top:1px solid var(--line);font-size:12px}.danger-link{text-align:center;color:var(--danger);font-size:12px;margin:22px}.mobile-card{text-align:center;background:var(--soft);margin:20px 16px;border-radius:14px;padding:26px}.mobile-card h1{font-size:34px;margin:5px 0}.mobile-card p{color:var(--muted);font-size:11px}.mobile-list{margin:0 16px;border:1px solid var(--line);border-radius:12px;overflow:hidden}.mobile-list>div{display:flex;justify-content:space-between;padding:14px;border-bottom:1px solid var(--line);font-size:11px}.mobile-list>div:last-child{border-bottom:0}.mobile-list span{color:var(--muted)}.notice{font-size:11px;line-height:1.5;color:var(--muted);margin:18px 22px}.mobile-wide{width:calc(100% - 32px);margin:10px 16px}
.payment-card>p{color:var(--muted);font-size:13px}.payment-methods{display:flex;flex-direction:column;gap:9px;margin:20px 0}.payment-method{border:1px solid var(--line);border-radius:10px;padding:13px;display:flex;gap:11px;align-items:center}.payment-method.selected{border-color:var(--accent);background:var(--accent-soft)}.payment-method strong{font-size:12px}.payment-method p{margin:3px 0 0;color:var(--muted);font-size:10px}.radio{width:17px;height:17px;border-radius:50%;border:1px solid #b8c1d1;display:block}.radio.on{border:5px solid var(--accent)}.demo-card{background:linear-gradient(135deg,#172a4c,#385e96);color:#fff;border-radius:14px;padding:18px;margin:20px 0}.card-top,.card-bottom{display:flex;justify-content:space-between;font-size:10px;letter-spacing:.08em;color:#cbd8ee}.demo-card>strong{display:block;margin:28px 0 18px;font-family:monospace;font-size:17px;letter-spacing:.06em}.receipt p{color:var(--muted);font-size:12px}.total-display{font-size:35px;font-weight:750;letter-spacing:-.04em;margin:14px 0 6px}.secure-note{margin-top:20px;background:#f1f8f4;color:var(--good);border-radius:9px;padding:12px;font-size:11px;display:flex;gap:8px;align-items:center}
.dashboard-grid{display:grid;grid-template-columns:1.4fr .8fr;gap:16px}.chart-card,.table-card{padding:20px}.bar-chart{height:150px;display:flex;align-items:flex-end;gap:12px;margin:20px 20px 8px;padding-top:12px;border-bottom:1px solid var(--line)}.bar-chart i{flex:1;background:linear-gradient(#6c8cff,#315efb);border-radius:5px 5px 0 0;min-height:20px}.chart-labels{display:flex;justify-content:space-between;color:var(--muted);font-size:9px;margin:0 18px}.axis-labels{display:none}.table-card table,.wide-table table,.incident-card table,.table-shell table{width:100%;border-collapse:collapse}.table-card th,.wide-table th,.incident-card th,.table-shell th{text-align:left;font-size:10px;text-transform:uppercase;letter-spacing:.08em;color:var(--muted);padding:12px 8px;border-bottom:1px solid var(--line)}.table-card td,.wide-table td,.incident-card td,.table-shell td{padding:13px 8px;border-bottom:1px solid var(--line);font-size:12px}
.ops-grid{display:grid;grid-template-columns:1.2fr .8fr;gap:16px}.service-panel,.region-panel{padding:20px}.service{display:grid;grid-template-columns:1fr auto auto;align-items:center;gap:16px;padding:12px 0;border-top:1px solid var(--line)}.service p{margin:3px 0 0;color:var(--muted);font-size:10px}.region-row{display:grid;grid-template-columns:86px 34px 1fr;align-items:center;gap:10px;margin:18px 0;font-size:11px}.region-row i{height:6px;background:var(--soft);border-radius:6px;overflow:hidden}.region-row em{display:block;height:100%;background:var(--accent);border-radius:6px}.incident-card{margin-top:16px;padding:20px}
.underlay{position:absolute;inset:74px 0 0 236px;padding:26px 28px}.blurred-card{padding:30px;max-width:780px}.blurred-card h3{color:var(--danger)}.modal-backdrop,.sheet-backdrop,.command-backdrop{position:fixed;inset:0;background:rgba(12,18,31,.48);display:grid;place-items:center;backdrop-filter:blur(3px)}.modal{width:460px;background:#fff;border-radius:16px;padding:26px;box-shadow:0 24px 80px rgba(0,0,0,.28)}.modal-icon{width:44px;height:44px;border-radius:12px;display:grid;place-items:center}.modal-icon.danger{background:#fff0f2;color:var(--danger)}.modal h2{font-size:21px;margin:16px 0 8px}.modal p{color:var(--muted);font-size:13px;line-height:1.5}.modal .field{margin:18px 0}.modal-actions{display:flex;justify-content:flex-end;gap:9px}.sheet-backdrop{align-items:flex-end}.sheet{width:100%;max-width:460px;background:#fff;border-radius:22px 22px 0 0;padding:9px 18px 24px;box-shadow:0 20px 80px rgba(0,0,0,.35)}.grabber{width:38px;height:4px;border-radius:4px;background:#cbd2df;margin:0 auto 18px}.sheet h2{font-size:19px;margin:0 0 5px}.sheet .panel-heading p{margin:0}.filter-section{margin:20px 0}.filter-section h3{font-size:12px;margin:0 0 9px}.chips{display:flex;flex-wrap:wrap;gap:7px}.chip{border:1px solid var(--line);border-radius:999px;background:#fff;padding:7px 10px;font-size:11px}.chip.active{background:var(--accent);border-color:var(--accent);color:#fff}.owner-row{display:flex;align-items:center;gap:10px;padding:8px 0;font-size:12px}.owner-row .switch{margin-left:auto}.mobile-search{margin:16px;background:var(--soft);border-radius:10px;padding:11px;display:flex;align-items:center;gap:8px;font-size:12px;color:var(--muted)}.skeleton{height:100px;margin:18px;background:#f1f4fa;border-radius:12px}.skeleton.short{height:60px}
.table-shell{padding:16px}.table-tools{display:flex;justify-content:space-between;align-items:center;margin-bottom:10px}.table-shell td small,.wide-table td small{display:block;color:var(--muted);font-size:10px;margin-top:3px}.icon-button{border:0;background:transparent;color:var(--muted)}.pagination{display:flex;justify-content:flex-end;align-items:center;gap:12px;padding:14px 4px;font-size:11px;color:var(--muted)}.pagination button{border:1px solid var(--line);background:#fff;border-radius:6px;padding:6px 9px}.notification-list{padding:0 14px}.notification{display:flex;gap:11px;padding:15px 5px;border-bottom:1px solid var(--line);position:relative}.notification.unread:after{content:"";position:absolute;right:1px;top:18px;width:6px;height:6px;border-radius:50%;background:var(--accent)}.notification-icon{width:34px;height:34px;border-radius:50%;background:var(--soft);display:grid;place-items:center}.notification>div{flex:1}.notification strong{font-size:12px}.notification p{margin:4px 0 0;color:var(--muted);font-size:11px}.notification .muted{font-size:9px}.mobile-tabs{margin:12px 16px}
.search-page{max-width:1050px;margin:0 auto}.search-hero{background:#fff;border:1px solid var(--line);border-radius:14px;padding:20px}.big-search{display:flex;align-items:center;gap:11px;border:1px solid var(--line);border-radius:10px;padding:12px;font-size:16px}.big-search .button{margin-left:auto}.tabs{display:flex;gap:20px;margin-top:16px}.tabs button{border:0;background:transparent;padding:7px 0;color:var(--muted);font-size:11px}.tabs button.active{color:var(--accent);border-bottom:2px solid var(--accent);font-weight:700}.result-count{font-size:11px;color:var(--muted);margin:16px 3px}.search-layout{display:grid;grid-template-columns:1fr 260px;gap:18px}.results{background:#fff;border:1px solid var(--line);border-radius:13px;padding:5px 18px}.result{display:flex;gap:13px;padding:17px 0;border-bottom:1px solid var(--line)}.result:last-child{border-bottom:0}.result-icon{width:36px;height:36px;border-radius:9px;background:var(--soft);display:grid;place-items:center}.result h3{font-size:15px;color:#2249d9;margin:5px 0}.result p{font-size:12px;line-height:1.45;color:var(--muted);margin:0 0 6px}.result small{font-size:10px}.search-layout aside{padding:18px}.search-layout aside h3{margin:0 0 13px}.search-layout aside p{font-size:11px;color:var(--muted);line-height:1.5}.empty-state{text-align:center;padding:70px 20px}.empty-icon{width:70px;height:70px;border-radius:50%;background:var(--accent-soft);color:var(--accent);display:grid;place-items:center;margin:0 auto 18px}.empty-icon .icon{width:30px;height:30px}.empty-state h2{font-size:22px;margin:0 0 8px}.empty-state p{color:var(--muted);font-size:13px}.empty-actions{display:flex;justify-content:center;gap:9px;margin:20px 0}.recent-searches{display:flex;gap:8px;justify-content:center;align-items:center;margin-top:34px;font-size:10px;color:var(--muted)}.recent-searches button{border:1px solid var(--line);background:#fff;border-radius:999px;padding:6px 9px}
.mail-app{display:grid;grid-template-columns:170px 320px 1fr;height:calc(100vh - 126px);background:#fff;border:1px solid var(--line);border-radius:13px;overflow:hidden}.mail-folders{padding:14px;background:#f8faff;border-right:1px solid var(--line)}.compose{width:100%;border:0;background:var(--accent);color:#fff;padding:10px;border-radius:8px;font-size:11px;font-weight:700;margin-bottom:16px}.mail-folders a{display:flex;align-items:center;gap:7px;padding:8px;border-radius:6px;font-size:11px;color:var(--muted)}.mail-folders a.active{background:var(--accent-soft);color:var(--accent)}.mail-folders b{margin-left:auto}.mail-list{border-right:1px solid var(--line);overflow:auto}.mail-head{padding:14px;display:flex;justify-content:space-between;align-items:center}.mail-head h2{margin:0;font-size:16px}.mail-head .searchbox{padding:7px}.mail-head input{width:130px}.mail-row{padding:12px 14px;border-top:1px solid var(--line)}.mail-row.active{background:var(--accent-soft)}.mail-row>div{display:flex;justify-content:space-between}.mail-row strong{font-size:11px}.mail-row span{color:var(--muted);font-size:9px}.mail-row b{display:block;font-size:11px;margin:5px 0}.mail-row p{font-size:10px;color:var(--muted);margin:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.mail-reader{padding:22px;overflow:auto}.reader-toolbar{display:flex;gap:6px;border-bottom:1px solid var(--line);padding-bottom:12px}.reader-toolbar button{border:1px solid var(--line);background:#fff;padding:6px 9px;border-radius:6px;font-size:10px}.mail-reader h1{font-size:26px;margin:10px 0 18px}.sender-line{display:flex;gap:10px;align-items:center;border-bottom:1px solid var(--line);padding-bottom:15px}.sender-line p{margin:3px 0;color:var(--muted);font-size:10px}.mail-reader>p{font-size:12px;line-height:1.65}.mail-reader blockquote{font-size:12px}.reply-box{display:flex;align-items:center;border:1px solid var(--line);border-radius:9px;padding:10px;color:var(--muted);font-size:11px}.reply-box .button{margin-left:auto}
.wide-settings{display:grid;grid-template-columns:200px 1fr 310px;gap:18px}.settings-nav.tall{background:#fff;border:1px solid var(--line);border-radius:13px;padding:16px}.settings-nav h3{font-size:12px;margin:0 0 12px}.teams-panel .page-head{margin-bottom:16px}.team-row{display:flex;align-items:center;gap:12px;padding:14px 18px;border-bottom:1px solid var(--line)}.team-row div:nth-child(2){flex:1}.team-row p{margin:3px 0;color:var(--muted);font-size:10px}.policy-panel{padding:20px;height:max-content}.policy-panel h3{margin:0 0 9px}.policy-panel p{font-size:12px;line-height:1.5;color:var(--muted)}.policy-panel label{display:flex;flex-direction:column;gap:6px;font-size:10px;margin:14px 0;color:var(--muted)}.policy-panel select{padding:8px;border:1px solid var(--line);border-radius:7px}.policy-panel .button{margin-top:12px}
.media-app .media-toolbar{display:flex;align-items:center;gap:12px;margin-bottom:14px}.media-toolbar strong{font-size:18px}.media-toolbar span{color:var(--muted);font-size:11px}.media-toolbar .button{margin-left:0}.media-toolbar .button.primary{margin-left:auto}.media-grid{display:grid;grid-template-columns:1fr 280px;gap:14px;height:calc(100vh - 170px)}.media-main{background:#fff;border:1px solid var(--line);border-radius:13px;padding:14px;display:flex;flex-direction:column}.preview-frame{background:linear-gradient(135deg,#182333,#4c6685 55%,#b8c7d6);flex:1;border-radius:9px;display:grid;place-items:center}.play{width:54px;height:54px;border-radius:50%;background:rgba(255,255,255,.85);display:grid;place-items:center;color:#1a2940;padding-left:4px}.timeline{display:flex;align-items:center;gap:10px;font-size:10px;color:var(--muted);margin:12px 0}.timeline div{height:5px;background:var(--soft);flex:1;border-radius:5px}.timeline i{display:block;height:100%;background:var(--accent)}.media-meta{display:flex;align-items:center;gap:8px}.media-meta h2{font-size:16px;margin:0}.media-meta p{font-size:10px;color:var(--muted);margin:3px 0}.media-meta button{border:1px solid var(--line);background:#fff;padding:7px 10px;border-radius:6px;font-size:10px}.clip-list{background:#fff;border:1px solid var(--line);border-radius:13px;padding:8px}.clip{display:grid;grid-template-columns:70px 1fr auto;gap:9px;align-items:center;padding:8px;border-radius:8px;font-size:11px}.clip.active{background:var(--accent-soft)}.thumb{height:45px;border-radius:5px;background:linear-gradient(135deg,#283e5c,#8fa3b8)}.thumb.two{background:linear-gradient(135deg,#7a573f,#cbb39c)}.thumb.three{background:linear-gradient(135deg,#4c5d50,#abc1ae)}.thumb.four{background:linear-gradient(135deg,#524862,#b6a9c2)}.clip small{color:var(--muted);font-size:9px}
.wide-table{padding:16px}.wide-table .table-tools{display:flex;justify-content:space-between}.wide-table .table-tools>div{display:flex;gap:8px}.wide-table td{font-size:13px;padding:15px 12px}.sparkline{display:flex;align-items:flex-end;gap:3px;height:20px}.sparkline i{width:5px;height:8px;background:#83a0ff;border-radius:2px}.sparkline i:nth-child(2){height:14px}.sparkline i:nth-child(3){height:11px}.sparkline i:nth-child(4){height:18px}
.legal-layout{display:grid;grid-template-columns:220px 1fr;gap:22px;max-width:1120px;margin:0 auto}.legal-toc{padding:8px 0}.legal-toc h3{font-size:12px;margin:0 0 12px}.legal-toc a{display:block;padding:7px 10px;font-size:11px;color:var(--muted);border-left:2px solid var(--line)}.legal-toc a.active{color:var(--accent);border-left-color:var(--accent)}.legal-doc{background:#fff;border:1px solid var(--line);border-radius:13px;padding:34px 48px}.legal-doc h1{font-size:28px;letter-spacing:-.03em}.legal-small{font-size:9px!important;color:#9099aa!important}.legal-note{font-size:9px;color:#9aa3b3;background:#f8f9fc;border-radius:7px;padding:10px;margin:16px 0}.legal-doc section h2{font-size:16px;margin:24px 0 8px}.legal-doc section p{font-size:9.5px;line-height:1.72;color:#737d8d;margin:0}
.soft-page{height:100%;display:grid;place-items:center;background:#eef1f5}.soft-card{width:620px;background:#f8f9fb;border:1px solid #e4e8ee;border-radius:16px;padding:34px;box-shadow:0 10px 30px rgba(30,40,60,.04)}.soft-eyebrow{font-size:10px;letter-spacing:.12em;color:#a1a9b6;font-weight:700}.soft-card h1{font-size:25px;margin:8px 0;color:#4c5667}.soft-card>p{font-size:12px;line-height:1.5;color:#a2aab7}.soft-field{display:flex;flex-direction:column;gap:6px;margin:18px 0;color:#8d96a5;font-size:11px}.soft-field input{border:1px solid #e5e8ed;background:#fbfcfd;border-radius:8px;padding:10px;color:#8993a2}.soft-check{display:flex;gap:8px;align-items:center;font-size:11px;color:#9ba4b2}.check-box{width:15px;height:15px;border-radius:4px;border:1px solid #dfe3e9;background:#fff;display:grid;place-items:center;color:#c1c7d0}.check-box .icon{width:10px;height:10px}.soft-button{width:100%;border:0;border-radius:8px;background:#c7d0e2;color:#f9fafc;padding:11px;margin-top:20px;font-weight:700;font-size:12px}.soft-help{font-size:10px!important;text-align:center;margin-top:15px;color:#b0b7c2!important}
.calendar-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:16px}.calendar-head h1{font-size:27px;margin:0}.view-toolbar{display:flex;gap:2px;background:#fff;border:1px solid var(--line);border-radius:9px;padding:3px}.view-toolbar button{border:0;background:transparent;padding:7px 9px;display:flex;align-items:center;gap:5px;font-size:10px;color:var(--muted);border-radius:6px}.calendar-shell{height:calc(100vh - 188px);background:#fff;border:1px solid var(--line);border-radius:13px;overflow:hidden}.weekdays{display:grid;grid-template-columns:repeat(7,1fr);border-bottom:1px solid var(--line);color:var(--muted);font-size:10px;text-transform:uppercase;letter-spacing:.08em}.weekdays span{padding:10px 12px;border-right:1px solid var(--line)}.calendar-grid{display:grid;grid-template-columns:repeat(7,1fr);grid-template-rows:repeat(5,1fr);height:calc(100% - 40px)}.calendar-day{padding:8px;border-right:1px solid var(--line);border-bottom:1px solid var(--line);font-size:11px;position:relative}.calendar-day.other{color:#c3c9d4;background:#fafbfd}.calendar-day.today span{background:var(--accent);color:#fff;border-radius:50%;width:22px;height:22px;display:grid;place-items:center}.calendar-day small{display:block;background:var(--accent-soft);color:var(--accent);padding:4px;border-radius:4px;margin-top:8px;font-size:9px}
.mobile-feed{background:#f6f7fa}.mobile-feed .mobile-head{padding:0 16px;background:#fff}.mobile-feed .mobile-head div{display:flex;gap:8px}.mobile-feed .mobile-head button{border:0;background:transparent}.stories{display:flex;gap:12px;padding:12px 16px;background:#fff;border-bottom:1px solid var(--line)}.story{width:58px;height:58px;border:2px solid #bdcaff;border-radius:50%;display:grid;place-items:center;font-size:8px;text-align:center;color:var(--muted)}.scroll-area{height:calc(100vh - 180px);overflow:auto;padding:10px 12px}.mobile-post{background:#fff;border:1px solid var(--line);border-radius:12px;padding:12px;margin-bottom:10px}.mobile-post .post-head{display:flex;gap:8px;align-items:center}.mobile-post .post-head div{display:flex;flex-direction:column;font-size:11px}.mobile-post p{font-size:11px;line-height:1.45}.mobile-photo{height:150px;border-radius:9px;background:linear-gradient(135deg,#7c91a6,#d1d9df)}.photo-1{background:linear-gradient(135deg,#9b7d63,#dbcdbc)}.photo-2{background:linear-gradient(135deg,#677b6c,#c3d0c4)}.post-actions{display:flex;gap:18px;margin-top:10px}.post-actions button{border:0;background:transparent;color:var(--muted);font-size:9px}.tabbar{position:absolute;bottom:0;left:0;right:0;height:54px;background:#fff;border-top:1px solid var(--line);display:flex;justify-content:space-around;align-items:center;font-size:9px;color:var(--muted)}.tabbar a.active{color:var(--accent);font-weight:700}.payment-sheet h2{font-size:19px;margin:0 0 16px}.payment-sheet .payment-method{margin-bottom:9px}.command-backdrop{background:rgba(8,12,21,.62)}.command-palette{width:620px;background:#131b2b;border:1px solid #2b3852;border-radius:14px;box-shadow:0 30px 100px rgba(0,0,0,.5);color:#e9eef8;overflow:hidden}.command-input{display:flex;align-items:center;gap:10px;padding:17px;border-bottom:1px solid #2b3852;color:#aeb9cc;font-size:14px}.command-input kbd{margin-left:auto;border:1px solid #394761;border-radius:5px;padding:3px 6px;font-size:9px}.command-label{display:block;padding:12px 16px 5px;color:#74819a;font-size:9px;letter-spacing:.12em}.command-row{display:flex;justify-content:space-between;align-items:center;padding:11px 14px;margin:0 4px;border-radius:8px;font-size:12px;color:#c3cddd}.command-row span{display:flex;align-items:center;gap:9px}.command-row.selected{background:#243251;color:#fff}.command-row kbd{font-size:10px;color:#8e9bb0}.command-footer{display:flex;gap:16px;border-top:1px solid #2b3852;padding:10px 16px;color:#74819a;font-size:9px}.dark{--bg:#0e1523;--panel:#151f30;--ink:#e8edf6;--muted:#8f9bb0;--line:#29364c;--soft:#1c2940;--accent:#7591ff;--accent-soft:#1d2a47}.dark .sidebar{background:#0b111c}.dark .searchbox,.dark .button.ghost,.dark .setting-row .select{background:#182337;color:#dbe4f2}.dark .metric,.dark .card,.dark .post,.dark .topbar,.dark .news-lead,.dark .news-card,.dark .outline,.dark .comments,.dark .paper,.dark .table-shell{background:#151f30}.dark .editor-toolbar{background:#151f30}.dark .paper blockquote{background:#1d2a47}.dark .paper,.dark .news-lead>div:not(.lead-image){color:#dbe4f2}.dark .segmented button.active{background:#26344c}.dark .skeleton{background:#1e2a3e}.dark .payment-method.selected{background:#1d2a47}.dark .demo-card{background:linear-gradient(135deg,#536c9d,#24395e)}
@media (max-width:700px){body{background:#fff}.app,.sidebar{display:none}.content{padding:0;overflow:hidden}.mobile-shell{max-width:none}.form-profile .mobile-form{overflow:auto}}
"""


INIT_SCRIPT = """
window.__cloudbaseClean = () => {
  const all = [...document.querySelectorAll('*')];
  for (const el of all) {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    if (s.display === 'none' || s.visibility === 'hidden' || Number(s.opacity) === 0 || r.width < 1 || r.height < 1) continue;
    if (r.right <= 0 || r.bottom <= 0 || r.left >= innerWidth || r.top >= innerHeight) continue;
    if (el.closest('[data-gt-ignore]')) continue;
    const direct = [...el.childNodes].filter(n => n.nodeType === Node.TEXT_NODE).map(n => n.textContent).join(' ').replace(/\\s+/g, ' ').trim();
    if (!direct || ['SCRIPT','STYLE','OPTION'].includes(el.tagName)) continue;
    el.setAttribute('data-gt-auto-text', '');
  }

  for (const group of document.querySelectorAll('[data-gt-group]')) {
    if (group.querySelectorAll('[data-gt-group-member]').length >= 2) continue;
    if (group.tagName === 'TBODY') {
      for (const row of group.children) row.setAttribute('data-gt-group-member', '');
      continue;
    }
    const axis = group.getAttribute('data-gt-group-axis') || 'vertical';
    for (const child of group.children) {
      if (child.classList.contains('panel-heading') || child.classList.contains('mail-head') || child.classList.contains('table-tools')) continue;
      const label = child.querySelector(':scope > .gt-row-label') || child.querySelector('.gt-row-label');
      if (axis === 'vertical' && label) label.setAttribute('data-gt-group-member', '');
      else if (child.getBoundingClientRect().width >= 2 && child.getBoundingClientRect().height >= 2) child.setAttribute('data-gt-group-member', '');
    }
  }
};
"""

EXTRACT_GT_JS = r"""
() => {
  const round = n => Math.round(n * 1e6) / 1e6;
  const box = el => {
    const r = el.getBoundingClientRect();
    return {
      x: round(r.left / innerWidth),
      y: round(r.top / innerHeight),
      width: round(r.width / innerWidth),
      height: round(r.height / innerHeight)
    };
  };
  const visible = el => {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return r.width >= 1 && r.height >= 1 && r.right > 0 && r.bottom > 0 && r.left < innerWidth && r.top < innerHeight && s.display !== 'none' && s.visibility !== 'hidden' && Number(s.opacity) > 0;
  };
  const text = [...document.querySelectorAll('[data-gt-auto-text]')].filter(visible).map((el, i) => ({
    id: `text_${i + 1}`,
    text: [...el.childNodes].filter(n => n.nodeType === Node.TEXT_NODE).map(n => n.textContent).join(' ').replace(/\s+/g, ' ').trim(),
    bbox: box(el)
  })).filter(x => x.text.length > 0);
  const containers = [...document.querySelectorAll('[data-gt-container]')].filter(visible).map((el, i) => ({
    id: el.getAttribute('data-gt-container') || `container_${i + 1}`,
    bbox: box(el),
    expected_evidence: 'inferred'
  }));
  const groups = [...document.querySelectorAll('[data-gt-group]')].map((el, i) => {
    const members = [...el.querySelectorAll('[data-gt-group-member]')].filter(visible);
    if (members.length < 2) return null;
    const boxes = members.map(box);
    const x = Math.min(...boxes.map(b => b.x));
    const y = Math.min(...boxes.map(b => b.y));
    const right = Math.max(...boxes.map(b => b.x + b.width));
    const bottom = Math.max(...boxes.map(b => b.y + b.height));
    return {
      id: el.getAttribute('data-gt-group') || `group_${i + 1}`,
      axis: el.getAttribute('data-gt-group-axis') || 'vertical',
      member_count: members.length,
      bbox: {x: round(x), y: round(y), width: round(right - x), height: round(bottom - y)}
    };
  }).filter(Boolean);
  return {text, containers, repeated_groups: groups};
}
"""


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def html_for(spec: dict[str, Any]) -> str:
    body = spec["body"]()
    if spec.get("mobile"):
        shell_html = body
    else:
        shell_html = shell(spec["title"], body, active=spec.get("active", "Home"), dark=spec.get("dark", False), wide=spec.get("wide", False))
    return f"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>{CSS}</style></head><body>{shell_html}</body></html>"""


def generate(verify_only: bool = False) -> None:
    if verify_only:
        manifest_path = DATASET / "manifest.json"
        if not manifest_path.exists():
            raise SystemExit("No manifest to verify")
        manifest = json.loads(manifest_path.read_text())
        for image in manifest["images"]:
            for key, rel in (("source_sha256", image["image"]), ("ground_truth_sha256", image["ground_truth"])):
                actual = sha256(DATASET / rel)
                if actual != image[key]:
                    raise SystemExit(f"SHA-256 mismatch for {rel}")
        parts = [f'{img["id"]}:{img["source_sha256"]}:{img["ground_truth_sha256"]}' for img in manifest["images"]]
        aggregate = hashlib.sha256("\n".join(parts).encode()).hexdigest()
        if aggregate != manifest["dataset_sha256"]:
            raise SystemExit("Dataset aggregate SHA-256 mismatch")
        print(f"Verified immutable dataset: {len(manifest['images'])} images, sha256={aggregate}")
        return

    from playwright.sync_api import sync_playwright

    IMAGES.mkdir(parents=True, exist_ok=True)
    GROUND_TRUTH.mkdir(parents=True, exist_ok=True)
    browser_path = os.environ.get("UI_BENCHMARK_BROWSER")
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, executable_path=browser_path) if browser_path else p.chromium.launch(headless=True)
        for spec in PAGES:
            page = browser.new_page(viewport={"width": spec["size"][0], "height": spec["size"][1]}, device_scale_factor=1)
            page.set_content(html_for(spec), wait_until="load")
            page.add_script_tag(content=INIT_SCRIPT)
            page.evaluate("() => window.__cloudbaseClean()")
            page.wait_for_timeout(80)
            truth = page.evaluate(EXTRACT_GT_JS)
            ext = "jpg" if spec["format"] == "jpeg" else "png"
            image_rel = f'images/{spec["id"]}.{ext}'
            truth_rel = f'ground_truth/{spec["id"]}.json'
            image_path = DATASET / image_rel
            truth_path = DATASET / truth_rel
            if spec["format"] == "jpeg":
                page.screenshot(path=str(image_path), type="jpeg", quality=88)
            else:
                page.screenshot(path=str(image_path), type="png")
            gt = {
                "schema": "ui_evidence_benchmark_ground_truth.v1",
                "id": spec["id"],
                "category": spec["category"],
                "tags": spec["tags"],
                "viewport": {"width": spec["size"][0], "height": spec["size"][1]},
                "image": image_rel,
                "mime_type": "image/jpeg" if spec["format"] == "jpeg" else "image/png",
                "source_kind": "web_screenshot",
                "crops": CROPS if not spec.get("mobile") else MOBILE_CROPS,
                **truth,
            }
            truth_path.write_text(json.dumps(gt, indent=2, ensure_ascii=False) + "\n")
            print(f"rendered {spec['id']} text={len(truth['text'])} containers={len(truth['containers'])} groups={len(truth['repeated_groups'])}")
            page.close()
        browser.close()

    entries = []
    for spec in PAGES:
        ext = "jpg" if spec["format"] == "jpeg" else "png"
        image_rel = f'images/{spec["id"]}.{ext}'
        truth_rel = f'ground_truth/{spec["id"]}.json'
        image_path = DATASET / image_rel
        truth_path = DATASET / truth_rel
        crops = CROPS if not spec.get("mobile") else MOBILE_CROPS
        entries.append({
            "id": spec["id"],
            "image": image_rel,
            "ground_truth": truth_rel,
            "mime_type": "image/jpeg" if spec["format"] == "jpeg" else "image/png",
            "source_kind": "web_screenshot",
            "source_sha256": sha256(image_path),
            "ground_truth_sha256": sha256(truth_path),
            "crops": crops,
        })
    parts = [f'{img["id"]}:{img["source_sha256"]}:{img["ground_truth_sha256"]}' for img in entries]
    aggregate = hashlib.sha256("\n".join(parts).encode()).hexdigest()
    manifest = {
        "schema_version": "ui_evidence_benchmark_dataset.v1",
        "name": "P1-C UI Evidence Quality Benchmark",
        "dataset_version": "1.0.0",
        "created_at": "2026-11-12",
        "immutable": True,
        "image_count": len(entries),
        "dataset_sha256": aggregate,
        "images": entries,
    }
    (DATASET / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote manifest: {len(entries)} images, sha256={aggregate}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    generate(verify_only=args.verify_only)


if __name__ == "__main__":
    main()
