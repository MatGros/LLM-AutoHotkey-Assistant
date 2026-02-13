window.chrome.webview.addEventListener('message', handleWebMessage);

// Initialize markdown-it with options
var md = window.markdownit({
  html: true,         // Enable HTML tags in source
  linkify: true,      // Autoconvert URL-like text to links
  typographer: true,  // Enable smartypants and other sweet transforms
  highlight: function (str, lang) {
    if (lang && hljs.getLanguage(lang)) {
      try {
        return '<pre class="hljs"><code>' +
          hljs.highlight(str, { language: lang, ignoreIllegals: true }).value +
          '</code></pre>';
      } catch (__) { }
    }
    return '<pre class="hljs"><code>' + md.utils.escapeHtml(str) + '</code></pre>';
  }
})
  .use(window.texmath, {  // Use texmath plugin for mathematical expressions
    engine: window.katex,
    delimiters: 'dollars',
    katexOptions: { macros: { "\\RR": "\\mathbb{R}" } }
  });

function renderMarkdown(content, ChatHistoryText) {
  // Define the content to render. Use the provided content or a default message
  var contentToRender = content || 'There is no content available.';

  // Save the pre-markdown text in localStorage for reloading later
  localStorage.setItem('preMarkdownText', contentToRender);

  // Render the markdown content
  var result = md.render(contentToRender);

  // Inject the rendered HTML into the target element
  var contentElement = document.getElementById('content');
  contentElement.innerHTML = result;

  // Scroll to the top
  contentElement.scrollTo(0, 0);

  // If ChatHistoryText, change button text to Chat History. Used by ShowResponseWindow in AutoHotkey
  var button = document.getElementById("chatHistoryButton");
  if (ChatHistoryText) {
    button.textContent = "Chat History";
  }
}

function responseWindowCopyButtonAction(copyAsMarkdown) {
  // Get the button element by its id
  var button = document.getElementById('copyButton');

  // Store the original button text
  var originalText = button.innerHTML;

  if (copyAsMarkdown) {
    // If copyAsMarkdown is true, just update the button without copying
    button.innerHTML = 'Copied!';
    button.disabled = true;

    // After 2 seconds, restore the original text and enable the button
    setTimeout(function () {
      button.innerHTML = originalText;
      button.disabled = false;
    }, 2000);
  } else {
    // Get the 'content' element
    var contentElement = document.getElementById('content');

    // Create a temporary element to hold the formatted content
    const tempElement = document.createElement('div');
    tempElement.innerHTML = contentElement.innerHTML;

    // Use the Clipboard API to write the HTML content to the clipboard
    navigator.clipboard.write([
      new ClipboardItem({
        'text/html': new Blob([tempElement.innerHTML], { type: 'text/html' }),
        'text/plain': new Blob([contentElement.innerText], { type: 'text/plain' })
      })
    ]).then(() => {
      // Change button text to "Copied!" and disable the button
      button.innerHTML = 'Copied!';
      button.disabled = true;

      // After 2 seconds, restore the original text and enable the button
      setTimeout(function () {
        button.innerHTML = originalText;
        button.disabled = false;
      }, 2000);
    });
  }
}

// Enables or disables the buttons and resets the cursor
function responseWindowButtonsEnabled(enable) {
  // Array of button IDs
  var buttonIds = ["chatButton", "copyButton", "retryButton", "chatHistoryButton"];

  // Iterate over each ID in the array
  buttonIds.forEach(function (id) {
    // Get the button element by ID
    var button = document.getElementById(id);

    // Check if the button exists to avoid errors
    if (button) {
      // Toggle the 'disabled' property using the ternary operator
      button.disabled = !enable;
    }
  });
  // Resets cursor
  document.body.style.cursor = 'auto';
}

function handleWebMessage(event) {
  try {
    // Name incoming data
    const message = event.data;

    // Check if data is an array for multiple parameters
    if (Array.isArray(message.data)) {
      if (typeof window[message.target] === 'function') {
        window[message.target](...message.data);
      } else {
        console.error(`Function "${message.target}" does not exist.`);
      }
    } else {
      // Existing single parameter handling
      if (typeof window[message.target] === 'function') {
        window[message.target](message.data);
      } else {
        console.error(`Function "${message.target}" does not exist.`);
      }
    }
  } catch (error) {
    console.error("Error handling incoming message:", error);
  }
}

// Toggle text button between Chat History and Latest Response
function toggleButtonText(ChatHistoryText) {
  var button = document.getElementById('chatHistoryButton');
  if (button.textContent === "Chat History") {
    button.textContent = "Latest Response";
  } else if (button.textContent === "Latest Response") {
    button.textContent = "Chat History";
    // Scroll to the top when displaying chat history
    document.getElementById('content').scrollTo(0, 0);
  } else if (ChatHistoryText) {
    button.textContent = "Chat History";
  }

  // Store the button text in localStorage so it persists across refreshes 
  localStorage.setItem('chatHistoryButtonText', button.textContent);
}

// Store button text before page refresh
window.addEventListener("beforeunload", function () {
  var button = document.getElementById("chatHistoryButton");
  if (button) {
    localStorage.setItem("chatHistoryButtonText", button.textContent);
  }
});

// ========================================
// Streaming functionality
// ========================================

var streamingContent = '';
var isStreaming = false;
var autoScrollEnabled = true;

// Start streaming - show initial loading message
function streamStart(modelName) {
  isStreaming = true;
  streamingContent = '';
  autoScrollEnabled = true;
  
  var contentElement = document.getElementById('content');
  contentElement.innerHTML = '<div class="streaming-indicator"><span class="streaming-dot"></span><span class="streaming-dot"></span><span class="streaming-dot"></span></div><div id="streaming-content" class="streaming-text"></div><span class="streaming-cursor">▊</span>';
  
  // Disable buttons during streaming
  responseWindowButtonsEnabled(false);
}

// Receive and display a chunk of streamed content
function streamChunk(chunk) {
  if (!isStreaming) return;
  
  streamingContent += chunk;
  
  // Render the accumulated content as markdown in real-time
  var result = md.render(streamingContent);
  
  var streamingDiv = document.getElementById('streaming-content');
  if (streamingDiv) {
    streamingDiv.innerHTML = result;
    
    // Auto-scroll to bottom if enabled and user hasn't scrolled up
    if (autoScrollEnabled) {
      var contentElement = document.getElementById('content');
      var isScrolledToBottom = contentElement.scrollHeight - contentElement.clientHeight <= contentElement.scrollTop + 100;
      if (isScrolledToBottom || contentElement.scrollTop === 0) {
        contentElement.scrollTo({
           top: contentElement.scrollHeight,
           behavior: 'smooth'
        });
      }
    }
  }
}

// End streaming - finalize display
function streamEnd(success) {
  isStreaming = false;
  
  if (success) {
    // Remove cursor and streaming indicator
    var contentElement = document.getElementById('content');
    var cursor = contentElement.querySelector('.streaming-cursor');
    var indicator = contentElement.querySelector('.streaming-indicator');
    if (cursor) cursor.remove();
    if (indicator) indicator.remove();
    
    // Final render of complete markdown
    var result = md.render(streamingContent);
    contentElement.innerHTML = result;
    
    // Save to localStorage
    localStorage.setItem('preMarkdownText', streamingContent);
    
    // Remove transparency via AHK handler
    if (typeof ahkHandler !== 'undefined') {
      ahkHandler.Func(JSON.stringify({ action: 'removeTransparency' }));
    }
  }
  
  // Re-enable buttons
  responseWindowButtonsEnabled(true);
  
  // Reset button text
  var button = document.getElementById("chatHistoryButton");
  button.textContent = "Chat History";
}

// Detect user scroll to disable auto-scroll
document.addEventListener("DOMContentLoaded", function () {
  var contentElement = document.getElementById('content');
  
  contentElement.addEventListener('wheel', function() {
    if (isStreaming) {
      autoScrollEnabled = false;
    }
  });
  
  // Retrieve pre-markdown text from localStorage and re-render
  var storedContent = localStorage.getItem('preMarkdownText');
  if (storedContent) {
    renderMarkdown(storedContent);
  }

  // Retrieve the button text from localStorage
  var storedButtonText = localStorage.getItem("chatHistoryButtonText");
  var button = document.getElementById("chatHistoryButton");
  if (storedButtonText) {
    button.textContent = storedButtonText;
  }
});