## Mandatory minimum

### Basic Website Setup
  - SPA (single page app) with Typescript frontend (moving around doesn’t reload the whole page, instead, JavaScript updates only the part of the page that changes)
  - Runs in Docker with one command (docker-compose up --build)
  - Works at least in Firefox, no visible errors  

### Pong Game Basics
  - Local Pong (2 players on same keyboard)  
  - Tournament system with aliases + matchmaking (organizes multiple players into a series of matches until a winner is decided, nicknames players type in before the tournament starts, the system automatically decides who plays against who, and in which order)
  - Same paddle speed for everyone  

### Security
  - Passwords hashed (“hashed” means you don’t store the real password in the database, e.g.: password = "hello123" → stored as "5d41402abc4b2a76b9719d911017c592")
  - Protection against SQL injection / XSS (login field: ' OR '1'='1 can trick and log them without password, <script>alert('Hacked!')</script>, webattacks)
  - HTTPS everywhere  
  - Input validation (client/server depending on setup) (user input checks: email, passwrod, alias/nickname, Client-side validation = checked in the browser with JavaScript before sending, Server-side validation = checked again on the backend)
  - Secrets in `.env` (not in git)  
