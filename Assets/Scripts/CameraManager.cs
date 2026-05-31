using UnityEngine;

public class CameraManager : MonoBehaviour
{
    public Camera[] cameras;
    private int activeIndex = 0;

    void Start()
    {
        // Solo la primera activa al inicio
        for (int i = 0; i < cameras.Length; i++)
            cameras[i].enabled = (i == 0);
    }

    void Update()
    {
        if (Input.GetKeyDown(KeyCode.Tab))
            SwitchToNext();
    }

    void SwitchToNext()
    {
        cameras[activeIndex].enabled = false;
        activeIndex = (activeIndex + 1) % cameras.Length;
        cameras[activeIndex].enabled = true;
    }
}