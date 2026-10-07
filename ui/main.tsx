import { createRoot } from 'react-dom/client';
import App from './App';
import './yami-kumo/styles.css';
import './dsh.css';

const root = document.getElementById('root');
if (!root) throw new Error('The dsh.mbt application root was not found.');

createRoot(root).render(<App />);
