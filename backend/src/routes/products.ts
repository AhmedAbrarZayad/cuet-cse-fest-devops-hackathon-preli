import express, { Request, Response } from 'express';
import { ProductModel } from '../models/product';
import validator from 'validator';

const router = express.Router();

// Create a product
router.post('/', async (req: Request, res: Response) => {
  try {
    const { name, price } = req.body;

    if (!name || typeof name !== 'string' || name.trim() === '') {
      return res.status(400).json({ error: 'Invalid name' });
    }

    if (typeof price !== 'number' || Number.isNaN(price) || price < 0) {
      return res.status(400).json({ error: 'Invalid price' });
    }

    const sanitizedName = validator.escape(name.trim());
    const p = new ProductModel({ name: sanitizedName, price });
    const saved = await p.save();
    console.log('Product saved:', saved);
    return res.status(201).json(saved);
  } catch (err) {
    console.error('POST /api/products error:', err);
    return res.status(500).json({ error: 'server error' });
  }
});

// List products
router.get('/', async (_req: Request, res: Response) => {
  try {
    const list = await ProductModel.find().sort({ createdAt: -1 }).lean();
    return res.json(list);
  } catch (err) {
    console.error('GET /api/products error:', err);
    return res.status(500).json({ error: 'server error' });
  }
});

export default router;

