import nodemailer from 'nodemailer';

export const handler = async (event) => {
  // Ahora usamos variables de entorno
  const transporter = nodemailer.createTransport({
    host: "smtp.gmail.com",
    port: 465,
    secure: true,
    auth: {
      user: process.env.EMAIL_USER, // Variable de entorno
      pass: process.env.EMAIL_PASS  // Variable de entorno
    }
  });

  for (const record of event.Records) {
    try {
      const body = JSON.parse(record.body);
      const placa = body.vehicle_plate || "No especificada";

      if (body.type === "Emergency") {
        await transporter.sendMail({
          from: `"Sistema de Alertas" <${process.env.EMAIL_USER}>`,
          to: process.env.EMAIL_RECEIVER, // Variable de entorno para el destino
          subject: "🚨 Alerta de Emergencia",
          text: `Emergencia detectada en vehículo: ${placa}`,
        });
      }
    } catch (error) {
      console.error("Error:", error);
    }
  }
};