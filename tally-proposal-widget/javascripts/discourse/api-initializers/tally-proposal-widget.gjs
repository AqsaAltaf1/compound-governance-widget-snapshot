import { apiInitializer } from "discourse/lib/api";

export default apiInitializer("1.8.0", (api) => {
  /**
   * Tally Proposal Widget
   * 
   * Conditions for showing the widget:
   * 1. Must be on a topic page (not homepage, user profiles, etc.)
   * 2. Must find a Tally proposal URL in the post
   * 3. Must successfully fetch proposal data from Tally API
   * 4. Must find or create a right sidebar to display the widget
   * 
   * If any condition fails, the widget will not be displayed.
   */
  
  const TALLY_API_URL = "https://api.tally.xyz/query";
  const TALLY_API_KEY = "afc402378b98d62f181eb36471e49c3705766c5d6a3bf4018d55c400e9b97a07";
  
  // Regex to match Tally proposal URLs
  // Supports formats like:
  // - https://www.tally.xyz/proposal/[id]
  // - https://tally.xyz/proposal/[id]
  // - https://www.tally.xyz/governance/[space]/proposal/[id]
  // - https://www.tally.xyz/governance/[space]/proposal/[slug]
  const TALLY_URL_REGEX = /https?:\/\/(?:www\.)?tally\.xyz\/(?:governance\/([^\/]+)\/)?proposal\/([a-zA-Z0-9_-]+)/gi;

  /**
   * Extract proposal ID and space from Tally URL
   * Returns { id, space } or null
   */
  function extractProposalInfo(url) {
    const match = TALLY_URL_REGEX.exec(url);
    if (!match) {
      TALLY_URL_REGEX.lastIndex = 0;
      return null;
    }
    
    // Reset regex for next use
    TALLY_URL_REGEX.lastIndex = 0;
    
    const space = match[1] || null; // Space ID (e.g., "arbitrum")
    const idOrSlug = match[2] || null; // Proposal ID or slug
    
    return {
      id: idOrSlug,
      space: space
    };
  }

  /**
   * GraphQL query to fetch proposal data by ID
   */
  async function fetchProposalDataById(proposalId) {
    const query = `
      query ProposalByTallyId($id: String!) {
        proposal(input: { id: $id }) {
          id
          onchainId
          status
          metadata {
            title
          }
          voteStats {
            type
            votesCount
            votersCount
            percent
          }
          quorum
        }
      }
    `;

    const variables = {
      id: proposalId
    };

    try {
      const response = await fetch(TALLY_API_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Api-Key": TALLY_API_KEY
        },
        body: JSON.stringify({
          query,
          variables
        })
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const data = await response.json();
      
      if (data.errors) {
        console.error("Tally API errors:", data.errors);
        return null;
      }

      return data.data?.proposal;
    } catch (error) {
      console.error("Error fetching Tally proposal by ID:", error);
      return null;
    }
  }

  /**
   * GraphQL query to fetch proposal data by space and slug/title
   * Fallback method when ID query fails
   */
  async function fetchProposalDataBySpaceAndSlug(spaceId, proposalSlug) {
    const query = `
      query ProposalBySlug($spaceId: String!, $proposalSlug: String!) {
        proposals(
          where: {
            space: $spaceId
            state: "all"
            title_contains: $proposalSlug
          }
          first: 1
          orderBy: "created"
          orderDirection: desc
        ) {
          id
          onchainId
          status
          metadata {
            title
          }
          voteStats {
            type
            votesCount
            votersCount
            percent
          }
          quorum
        }
      }
    `;

    const variables = {
      spaceId: spaceId,
      proposalSlug: proposalSlug
    };

    try {
      const response = await fetch(TALLY_API_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Api-Key": TALLY_API_KEY
        },
        body: JSON.stringify({
          query,
          variables
        })
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const data = await response.json();
      
      if (data.errors) {
        console.error("Tally API errors:", data.errors);
        return null;
      }

      const proposals = data.data?.proposals;
      return proposals && proposals.length > 0 ? proposals[0] : null;
    } catch (error) {
      console.error("Error fetching Tally proposal by space/slug:", error);
      return null;
    }
  }

  /**
   * Main function to fetch proposal data
   * Tries ID first, then falls back to space/slug if needed
   */
  async function fetchProposalData(proposalInfo) {
    // First, try fetching by ID directly
    let proposal = await fetchProposalDataById(proposalInfo.id);
    
    // If that fails and we have space info, try by space and slug
    if (!proposal && proposalInfo.space) {
      proposal = await fetchProposalDataBySpaceAndSlug(proposalInfo.space, proposalInfo.id);
    }
    
    return proposal;
  }

  /**
   * Format large numbers (e.g., 216624044462525248865899428 -> 8.5M)
   */
  function formatVoteCount(count) {
    if (!count) return "0";
    const num = typeof count === "string" ? parseFloat(count) : count;
    if (num >= 1000000000) return (num / 1000000000).toFixed(1) + "B";
    if (num >= 1000000) return (num / 1000000).toFixed(1) + "M";
    if (num >= 1000) return (num / 1000).toFixed(1) + "K";
    return num.toString();
  }

  /**
   * Calculate total votes for progress bar
   */
  function calculateTotalVotes(voteStats) {
    return voteStats.reduce((total, stat) => {
      if (stat.type !== "pendingfor" && stat.type !== "pendingagainst") {
        const votes = typeof stat.votesCount === "string" 
          ? parseFloat(stat.votesCount) 
          : stat.votesCount;
        return total + (votes || 0);
      }
      return total;
    }, 0);
  }

  /**
   * Create HTML for proposal embed (Gitcoin-style sidebar)
   */
  function createProposalEmbed(proposal, originalUrl, currentIndex = 1, totalCount = 1) {
    if (!proposal) return null;

    const title = proposal.metadata?.title || "Untitled Proposal";
    const status = proposal.status || "unknown";
    const voteStats = proposal.voteStats || [];
    
    // Filter out pending votes
    const activeVoteStats = voteStats.filter(
      stat => stat.type !== "pendingfor" && stat.type !== "pendingagainst"
    );
    
    const totalVotes = calculateTotalVotes(activeVoteStats);
    
    // Get individual vote stats
    const forStat = activeVoteStats.find(s => s.type === "for") || { votesCount: "0", votersCount: 0, percent: 0 };
    const againstStat = activeVoteStats.find(s => s.type === "against") || { votesCount: "0", votersCount: 0, percent: 0 };
    const abstainStat = activeVoteStats.find(s => s.type === "abstain") || { votesCount: "0", votersCount: 0, percent: 0 };
    
    const forVotes = formatVoteCount(forStat.votesCount);
    const againstVotes = formatVoteCount(againstStat.votesCount);
    const abstainVotes = formatVoteCount(abstainStat.votesCount);
    
    const forPercent = forStat.percent || 0;
    const againstPercent = againstStat.percent || 0;
    const abstainPercent = abstainStat.percent || 0;
    
    // Calculate progress bar widths
    const forWidth = totalVotes > 0 ? (forPercent / 100) * 100 : 0;
    const againstWidth = totalVotes > 0 ? (againstPercent / 100) * 100 : 0;
    const abstainWidth = totalVotes > 0 ? (abstainPercent / 100) * 100 : 0;

    // Status badge color
    const statusClass = status.toLowerCase().replace(/\s+/g, "-");
    const statusLabel = status.charAt(0).toUpperCase() + status.slice(1).replace(/([A-Z])/g, " $1").trim();

    return `
      <div class="tally-proposal-sidebar" data-proposal-id="${proposal.id}">
        <div class="tally-proposal-status-header">
          <span class="tally-status-badge tally-status-badge--${statusClass}">${statusLabel}</span>
          <span class="tally-proposal-pagination">${currentIndex}/${totalCount}</span>
        </div>
        
        <div class="tally-proposal-voting-section">
          <div class="tally-vote-result tally-vote-result--for">
            <span class="tally-vote-label">For</span>
            <span class="tally-vote-value">${forVotes}</span>
          </div>
          <div class="tally-vote-result tally-vote-result--against">
            <span class="tally-vote-label">Against</span>
            <span class="tally-vote-value">${againstVotes}</span>
          </div>
          <div class="tally-vote-result tally-vote-result--abstain">
            <span class="tally-vote-label">Abstain</span>
            <span class="tally-vote-value">${abstainVotes}</span>
          </div>
          
          <div class="tally-progress-bar">
            <div class="tally-progress-segment tally-progress-segment--for" style="width: ${forWidth}%"></div>
            <div class="tally-progress-segment tally-progress-segment--against" style="width: ${againstWidth}%"></div>
            <div class="tally-progress-segment tally-progress-segment--abstain" style="width: ${abstainWidth}%"></div>
          </div>
          
          <a href="${originalUrl}" target="_blank" rel="noopener noreferrer" class="tally-vote-button">
            Vote on Tally
          </a>
        </div>
        
        <div class="tally-proposal-meta">
          <div class="tally-meta-item">
            <span class="tally-meta-label">Proposal ID</span>
            <span class="tally-meta-value">${proposal.id}</span>
          </div>
          ${proposal.onchainId ? `
            <div class="tally-meta-item">
              <span class="tally-meta-label">On-chain ID</span>
              <span class="tally-meta-value tally-meta-value--truncate">${proposal.onchainId}</span>
            </div>
          ` : ""}
          ${proposal.quorum ? `
            <div class="tally-meta-item">
              <span class="tally-meta-label">Quorum</span>
              <span class="tally-meta-value">${formatVoteCount(proposal.quorum)}</span>
            </div>
          ` : ""}
        </div>
      </div>
    `;
  }

  /**
   * Find the post container for a given element
   */
  function findPostContainer(element) {
    let current = element;
    while (current && current !== document.body) {
      if (current.classList && (
        current.classList.contains("topic-post") ||
        current.classList.contains("post") ||
        current.classList.contains("cooked") ||
        current.classList.contains("post-content")
      )) {
        return current;
      }
      current = current.parentElement;
    }
    return null;
  }

  /**
   * Find or create the Discourse right sidebar (timeline container)
   */
  function findOrCreateRightSidebar() {
    // Strategy 1: Look for elements containing pagination text like "11/11" (Discourse timeline indicator)
    const allElements = document.querySelectorAll("*");
    for (const elem of allElements) {
      const text = elem.textContent || "";
      // Check if element contains pagination pattern (e.g., "11/11", "7/10")
      if (text.match(/^\d+\/\d+$/) || (text.match(/\d+\/\d+/) && elem.children.length === 0)) {
        // Found pagination text, find its parent container (the timeline)
        let parent = elem.parentElement;
        let timeline = null;
        
        // Walk up the DOM to find the timeline container
        while (parent && parent !== document.body) {
          const rect = parent.getBoundingClientRect();
          const windowWidth = window.innerWidth;
          
          // Check if this parent is positioned on the right side
          if (rect.left > windowWidth * 0.6 && rect.width > 0 && rect.height > 0) {
            // This looks like the timeline container
            timeline = parent;
            break;
          }
          parent = parent.parentElement;
        }
        
        if (timeline) {
          console.log("Tally Proposal Widget: Found timeline by pagination text", timeline);
          return timeline;
        }
      }
    }
    
    // Strategy 2: Try to find existing sidebar with multiple selectors
    const possibleSelectors = [
      ".topic-timeline-container",
      ".timeline-container", 
      ".topic-timeline",
      ".timeline",
      "[data-timeline]",
      ".topic-sidebar",
      ".right-sidebar",
      "aside[role='complementary']",
      "aside.timeline",
      "div.timeline",
      "[class*='timeline']"
    ];
    
    // Also check for elements positioned on the right side
    const rightSideElements = document.querySelectorAll("aside, [class*='timeline'], [class*='sidebar']");
    for (const elem of rightSideElements) {
      const rect = elem.getBoundingClientRect();
      const windowWidth = window.innerWidth;
      // Check if element is on the right side (last 30% of screen)
      if (rect.left > windowWidth * 0.7 && rect.width > 0 && rect.height > 0) {
        // Check if it looks like a timeline (has numbers like "11/11" or timeline markers)
        const text = elem.textContent || "";
        if (text.match(/\d+\/\d+/) || elem.querySelector("[class*='timeline']") || elem.classList.contains("timeline")) {
          console.log("Tally Proposal Widget: Found timeline by position and content", elem);
          return elem;
        }
      }
    }
    
    for (const selector of possibleSelectors) {
      const sidebar = document.querySelector(selector);
      if (sidebar) {
        // Verify it's actually visible and on the right side
        const rect = sidebar.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
          // Double check it's on the right
          const windowWidth = window.innerWidth;
          if (rect.left > windowWidth * 0.6) {
            return sidebar;
          }
        }
      }
    }
    
    // If not found, find the main content area and create sidebar next to it
    const contentSelectors = [
      ".topic-body",
      ".post-stream", 
      ".posts-wrapper",
      ".topic-post",
      "[data-topic-id]"
    ];
    
    let contentArea = null;
    for (const selector of contentSelectors) {
      contentArea = document.querySelector(selector);
      if (contentArea) break;
    }
    
    if (!contentArea) {
      // Last resort: find any main content container
      contentArea = document.querySelector("main, .main-content, .content");
    }
    
    if (contentArea) {
      // Find the parent container that we can modify
      let parent = contentArea.parentElement;
      let wrapper = null;
      
      // Look for a suitable wrapper (skip body and html)
      while (parent && parent !== document.body && parent !== document.documentElement) {
        const style = window.getComputedStyle(parent);
        // Check if this looks like a container we can modify
        if (style.display !== "none" && (parent.offsetWidth > 600 || parent.classList.length > 0)) {
          wrapper = parent;
          break;
        }
        parent = parent.parentElement;
      }
      
      if (!wrapper) {
        wrapper = contentArea.parentElement;
      }
      
      // Check if sidebar already exists in wrapper
      const existingSidebar = wrapper.querySelector(".tally-custom-sidebar, .tally-proposal-widget-container");
      if (existingSidebar) {
        return existingSidebar.closest("aside") || existingSidebar;
      }
      
      // Create custom sidebar
      const sidebar = document.createElement("aside");
      sidebar.className = "tally-custom-sidebar";
      sidebar.setAttribute("role", "complementary");
      sidebar.setAttribute("aria-label", "Tally Proposal Widget");
      
      // Set up flex layout
      const currentDisplay = window.getComputedStyle(wrapper).display;
      if (currentDisplay !== "flex" && currentDisplay !== "grid") {
        wrapper.style.display = "flex";
        wrapper.style.gap = "2em";
        wrapper.style.alignItems = "flex-start";
      }
      
      // Make content area flexible
      if (currentDisplay !== "grid") {
        contentArea.style.flex = "1";
        contentArea.style.minWidth = "0";
      }
      
      // Style sidebar
      sidebar.style.cssText = `
        flex: 0 0 320px;
        position: sticky;
        top: 1em;
        align-self: flex-start;
        max-height: calc(100vh - 2em);
        overflow-y: auto;
        display: block;
        visibility: visible;
        z-index: 10;
      `;
      
      // Insert sidebar after content area
      if (wrapper.lastChild === contentArea) {
        wrapper.appendChild(sidebar);
      } else {
        wrapper.insertBefore(sidebar, contentArea.nextSibling);
      }
      
      return sidebar;
    }
    
    return null;
  }

  /**
   * Process a single link element and create sidebar layout
   */
  async function processTallyLink(linkElement) {
    // Skip if already processed
    if (linkElement.dataset.tallyProcessed === "true") {
      return;
    }

    const url = linkElement.href;
    const proposalInfo = extractProposalInfo(url);

    if (!proposalInfo || !proposalInfo.id) {
      return;
    }

    // Mark as processed to avoid duplicate requests
    linkElement.dataset.tallyProcessed = "true";

    // Add loading state
    linkElement.classList.add("tally-loading");

    // Find the post container
    const postContainer = findPostContainer(linkElement);
    if (!postContainer) {
      linkElement.classList.remove("tally-loading");
      return;
    }

    // Only process on topic pages
    if (!isTopicPage()) {
      linkElement.classList.remove("tally-loading");
      return;
    }

    // Fetch proposal data
    const proposal = await fetchProposalData(proposalInfo);

    if (!proposal) {
      console.warn("Tally Proposal Widget: Failed to fetch proposal data", proposalInfo);
      linkElement.classList.remove("tally-loading");
      return;
    }

    // Count total Tally proposals across all posts for pagination
    const topicContainer = document.querySelector(".topic-container, .topic, [data-topic-id]") || document;
    const allTallyLinks = Array.from(topicContainer.querySelectorAll("a[href*='tally.xyz']"));
    const processedLinks = allTallyLinks.filter(link => link.dataset.tallyProcessed === "true");
    const totalCount = allTallyLinks.length;
    const currentIndex = processedLinks.length + 1;

    const embedHtml = createProposalEmbed(proposal, url, currentIndex, totalCount);
    
    if (!embedHtml) {
      console.warn("Tally Proposal Widget: Failed to create embed HTML");
      linkElement.classList.remove("tally-loading");
      return;
    }

    // Try to find or create the right sidebar
    let rightSidebar = findOrCreateRightSidebar();
    
    if (rightSidebar) {
          // Check if widget container already exists
          let widgetContainer = rightSidebar.querySelector(".tally-proposal-widget-container");
          
          if (!widgetContainer) {
            // Create widget container
            widgetContainer = document.createElement("div");
            widgetContainer.className = "tally-proposal-widget-container";
            
            // Try to insert at the top of the sidebar, or append if no good insertion point
            const firstChild = rightSidebar.firstElementChild;
            if (firstChild && firstChild.tagName !== "SCRIPT" && firstChild.tagName !== "STYLE") {
              rightSidebar.insertBefore(widgetContainer, firstChild);
            } else {
              rightSidebar.appendChild(widgetContainer);
            }
          }
          
          // Add or update the widget
          widgetContainer.innerHTML = embedHtml;
          
          // Make sure sidebar and widget are visible
          rightSidebar.style.display = "";
          rightSidebar.style.visibility = "";
          rightSidebar.style.opacity = "";
          widgetContainer.style.display = "block";
          widgetContainer.style.visibility = "visible";
          
          console.log("Tally Proposal Widget: Widget added to sidebar", rightSidebar, widgetContainer);
        } else {
          // Fallback: log for debugging
          console.warn("Tally Proposal Widget: Could not find or create sidebar");
          console.warn("Tally Proposal Widget: Available elements:", {
            timeline: document.querySelector(".timeline, .topic-timeline, [class*='timeline']"),
            aside: document.querySelectorAll("aside"),
            rightSide: Array.from(document.querySelectorAll("*")).filter(el => {
              const rect = el.getBoundingClientRect();
              return rect.left > window.innerWidth * 0.7;
            }).slice(0, 5)
          });
          
          // Retry after a delay - Discourse might not have rendered timeline yet
          setTimeout(() => {
            const retrySidebar = findOrCreateRightSidebar();
            if (retrySidebar) {
              let widgetContainer = retrySidebar.querySelector(".tally-proposal-widget-container");
              if (!widgetContainer) {
                widgetContainer = document.createElement("div");
                widgetContainer.className = "tally-proposal-widget-container";
                const firstChild = retrySidebar.firstElementChild;
                if (firstChild && firstChild.tagName !== "SCRIPT" && firstChild.tagName !== "STYLE") {
                  retrySidebar.insertBefore(widgetContainer, firstChild);
                } else {
                  retrySidebar.appendChild(widgetContainer);
                }
              }
              widgetContainer.innerHTML = embedHtml;
              console.log("Tally Proposal Widget: Widget added to sidebar on retry", retrySidebar);
            } else {
              // Final fallback: create inline layout if sidebar still not available
              console.warn("Tally Proposal Widget: Using fallback inline layout");
              const cookedContent = postContainer.querySelector(".cooked, .post-content");
              if (cookedContent) {
                let layoutWrapper = cookedContent.closest(".tally-proposal-layout");
                
                if (!layoutWrapper) {
                  layoutWrapper = document.createElement("div");
                  layoutWrapper.className = "tally-proposal-layout";
                  
                  const leftColumn = document.createElement("div");
                  leftColumn.className = "tally-proposal-content-column";
                  
                  const rightColumn = document.createElement("div");
                  rightColumn.className = "tally-proposal-sidebar-column";
                  
                  const parent = cookedContent.parentElement;
                  const nextSibling = cookedContent.nextSibling;
                  
                  leftColumn.appendChild(cookedContent);
                  layoutWrapper.appendChild(leftColumn);
                  layoutWrapper.appendChild(rightColumn);
                  
                  if (nextSibling) {
                    parent.insertBefore(layoutWrapper, nextSibling);
                  } else {
                    parent.appendChild(layoutWrapper);
                  }
                }
                
                const rightColumn = layoutWrapper.querySelector(".tally-proposal-sidebar-column");
                if (rightColumn) {
                  rightColumn.innerHTML = embedHtml;
                }
              }
            }
          }, 1000);
        }
        
        // Hide the original link
        linkElement.style.display = "none";
      }
    }

    // Remove loading state
    linkElement.classList.remove("tally-loading");
  }

  /**
   * Process all Tally links in a container
   */
  function processTallyLinks(container) {
    if (!container) return;

    const links = container.querySelectorAll("a[href*='tally.xyz']");
    links.forEach(link => {
      processTallyLink(link);
    });
  }

  /**
   * Check if we're on a topic page
   */
  function isTopicPage() {
    // Check URL pattern
    const path = window.location.pathname;
    if (path.match(/^\/t\/.+\/\d+/)) {
      return true;
    }
    
    // Check for topic-specific elements
    const topicIndicators = [
      ".topic-post",
      ".topic-body",
      ".post-stream",
      "[data-topic-id]",
      ".topic-container"
    ];
    
    for (const selector of topicIndicators) {
      if (document.querySelector(selector)) {
        return true;
      }
    }
    
    return false;
  }

  /**
   * Initialize the widget
   */
  function initializeTallyWidget() {
    // Only initialize on topic pages
    if (!isTopicPage()) {
      return;
    }
    
    // Process existing posts
    const posts = document.querySelectorAll(".cooked, .post-content");
    posts.forEach(post => {
      processTallyLinks(post);
    });

    // Watch for new posts (using MutationObserver)
    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType === Node.ELEMENT_NODE) {
            // Check if the node itself is a cooked post
            if (node.matches && (node.matches(".cooked") || node.matches(".post-content"))) {
              processTallyLinks(node);
            }
            // Check for Tally links within the node
            processTallyLinks(node);
          }
        });
      });
    });

    // Observe the main content area
    const mainContent = document.querySelector(".topic-post, .post-stream, .topic-body");
    if (mainContent) {
      observer.observe(mainContent, {
        childList: true,
        subtree: true
      });
    }

    // Also observe the entire document body as fallback
    observer.observe(document.body, {
      childList: true,
      subtree: true
    });
  }

  // Initialize when DOM is ready
  function startInitialization() {
    // Wait a bit for Discourse to render
    setTimeout(() => {
      initializeTallyWidget();
      // Also retry after a longer delay in case Discourse is still loading
      setTimeout(initializeTallyWidget, 1000);
    }, 100);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", startInitialization);
  } else {
    startInitialization();
  }

  // Re-initialize on navigation (Discourse uses Ember, so we hook into route changes)
  api.onPageChange(() => {
    setTimeout(() => {
      initializeTallyWidget();
      // Retry after delay
      setTimeout(initializeTallyWidget, 500);
    }, 200);
  });
});


